"""Sudoless measurements of an Apple silicon Mac, shared by perf-journal.py and jobgate.py.

Memory per process is the phys_footprint (Activity Monitor's Memory column, what jetsam counts): RSS leaves out
compressed pages and Metal buffers (a 30 GB MPS job showed 0.2 GB of RSS). Memory availability is the kernel's
own kern.memorystatus_level (the "free percentage" of memory_pressure); kern.memorystatus_vm_pressure_level is
1 normal, 2 warn, 4 critical (the levels of DISPATCH_SOURCE_TYPE_MEMORYPRESSURE)."""
import ctypes, ctypes.util, os, re, subprocess, sys

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
# macOS only; elsewhere (the Linux CI runs jobgate's pure-logic self-test) the module imports, the probes do not.
MACOS = sys.platform == "darwin"
libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True) if MACOS else None


class RusageV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size", "resident_size",
        "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time", "child_system_time",
        "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins", "child_elapsed_abstime",
        "diskio_bytesread", "diskio_byteswritten")]


class _Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_tb = _Timebase(1, 1)
if MACOS:
    libc.mach_timebase_info(ctypes.byref(_tb))
TICK_NS = _tb.numer / _tb.denom  # rusage times are mach ticks (125/3 ns on Apple silicon)


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout


def sysctl_int(name):
    if not MACOS:
        return None
    v = ctypes.c_int64(0)
    size = ctypes.c_size_t(8)
    if libc.sysctlbyname(name.encode(), ctypes.byref(v), ctypes.byref(size), None, 0) != 0:
        return None
    return v.value if size.value == 8 else ctypes.c_int32.from_buffer(v).value


RAM = sysctl_int("hw.memsize") or os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
NCPU = sysctl_int("hw.ncpu") or os.cpu_count()


def kernel_free_pct():
    return sysctl_int("kern.memorystatus_level")


def pressure_level():
    return sysctl_int("kern.memorystatus_vm_pressure_level")


def pids():
    n = libproc.proc_listallpids(None, 0)
    buf = (ctypes.c_int * (n + 64))()
    n = libproc.proc_listallpids(buf, ctypes.sizeof(buf))
    return [p for p in buf[:n] if p > 0]


def children(pid):
    buf = (ctypes.c_int * 4096)()
    n = libproc.proc_listchildpids(pid, buf, ctypes.sizeof(buf))
    return [p for p in buf[:max(n, 0)] if p > 0]


def tree(pid):
    """pid and all its descendants."""
    out, todo = [], [pid]
    while todo:
        p = todo.pop()
        out.append(p)
        todo += children(p)
    return out


def rusage(pid):
    ru = RusageV2()
    if libproc.proc_pid_rusage(pid, 2, ctypes.byref(ru)) != 0:
        return None
    return ru


def footprint(pid):
    ru = rusage(pid)
    return ru.phys_footprint if ru else 0


def tree_footprint(pid):
    return sum(footprint(p) for p in tree(pid))


def tree_cpu_s(pid):
    return sum((ru.user_time + ru.system_time) * TICK_NS / 1e9 for p in tree(pid) if (ru := rusage(p)))


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def name(pid):
    buf = ctypes.create_string_buffer(4096)
    if libproc.proc_pidpath(pid, buf, 4096) > 0:
        path = buf.value.decode(errors="replace")
        if "/claude/versions/" in path:  # the Claude Code binary is named after its version (2.1.310)
            return "claude"
        return os.path.basename(path)
    buf = ctypes.create_string_buffer(64)
    libproc.proc_name(pid, buf, 64)
    return buf.value.decode(errors="replace") or "?"


def args(pid):
    """argv of a process (KERN_PROCARGS2)."""
    mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t(1 << 16)
    buf = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
        return ""
    raw = buf.raw[:size.value]
    argc = int.from_bytes(raw[:4], "little")
    parts = [p for p in raw[4:].split(b"\0") if p][1:argc + 1]  # skip the exec path
    return " ".join(p.decode(errors="replace") for p in parts)[:160]


def cwd(pid):
    """Working directory (PROC_PIDVNODEPATHINFO: vnode_info_path cdir = 152-byte vnode_info + 1024-byte path)."""
    buf = ctypes.create_string_buffer(2352)
    if libproc.proc_pidinfo(pid, 9, ctypes.c_uint64(0), buf, 2352) <= 0:
        return ""
    return buf.raw[152:1176].split(b"\0", 1)[0].decode(errors="replace")


class _Host:
    count = ctypes.c_uint32()
    info = ctypes.POINTER(ctypes.c_int32)()
    n = ctypes.c_uint32()


def cpu_ticks():
    """Whole-machine user/system/idle/nice ticks (host_processor_info). kernel_task (pid 0) is not readable
    without root; the system share carries its work, memory compression included."""
    h = _Host()
    libc.host_processor_info(libc.mach_host_self(), 2, ctypes.byref(h.count), ctypes.byref(h.info), ctypes.byref(h.n))
    t = [0, 0, 0, 0]  # CPU_STATE_USER, SYSTEM, IDLE, NICE
    for i in range(h.count.value * 4):
        t[i % 4] += h.info[i]
    libc.vm_deallocate(ctypes.c_uint.in_dll(libc, "mach_task_self_"), ctypes.cast(h.info, ctypes.c_void_p),
                       ctypes.c_size_t(h.n.value * 4))
    return t


def vm():
    """vm_stat page counts and the page size."""
    out = run("/usr/bin/vm_stat")
    page = int(re.search(r"page size of (\d+)", out).group(1))
    return page, {m.group(1): int(m.group(2)) for m in re.finditer(r"^(.+?):\s+(\d+)\.", out, re.M)}


def swap_used_gb():
    m = re.search(r"used = ([\d.]+)M", run("/usr/sbin/sysctl", "-n", "vm.swapusage"))
    return round(float(m.group(1)) / 1024, 2) if m else None


def gpu():
    """Utilisation and memory (IOAccelerator statistics), and cumulative GPU time per pid (AGXDeviceUserClient)."""
    stats = run("/usr/sbin/ioreg", "-r", "-d1", "-c", "IOAccelerator")
    num = lambda k: int(m.group(1)) if (m := re.search(rf'"{re.escape(k)}"=(\d+)', stats)) else None
    per_pid = {}
    clients = run("/usr/sbin/ioreg", "-r", "-c", "AGXDeviceUserClient", "-l")
    for block in clients.split("+-o AGXDeviceUserClient")[1:]:
        m = re.search(r'"IOUserClientCreator" = "pid (\d+), ([^"]*)"', block)
        if m:
            t = sum(int(x) for x in re.findall(r'"accumulatedGPUTime"=(\d+)', block))
            per_pid[int(m.group(1))] = per_pid.get(int(m.group(1)), 0) + t
    return {"util": num("Device Utilization %"), "inuse_gb": round((num("In use system memory") or 0) / 1e9, 2),
            "alloc_gb": round((num("Alloc system memory") or 0) / 1e9, 2)}, per_pid


def gpu_util():
    m = re.search(r'"Device Utilization %"=(\d+)', run("/usr/sbin/ioreg", "-r", "-d1", "-c", "IOAccelerator"))
    return int(m.group(1)) if m else None


def metal_recommended_max():
    """MTLDevice.recommendedMaxWorkingSetSize: what PyTorch MPS and MLX size their limits from (55.7 GB on a
    64 GB M5 Max). Read through the Objective-C runtime, no PyObjC needed."""
    try:
        metal = ctypes.CDLL("/System/Library/Frameworks/Metal.framework/Metal")
        objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
        metal.MTLCreateSystemDefaultDevice.restype = ctypes.c_void_p
        dev = metal.MTLCreateSystemDefaultDevice()
        if not dev:
            return None
        objc.sel_registerName.restype = ctypes.c_void_p
        sel = objc.sel_registerName(b"recommendedMaxWorkingSetSize")
        send = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_void_p, ctypes.c_void_p)(("objc_msgSend", objc))
        return send(dev, sel)
    except (OSError, AttributeError):
        return None

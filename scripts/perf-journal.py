#!/usr/bin/env python3
"""Performance journal: one sample a minute of what really uses the Mac's memory, CPU and GPU, per process.

Activity Monitor shows the present; this keeps a week of history so that an optimisation is judged on numbers
before and after, not on an impression. Sudoless and cheap (about 0.1 s of CPU a sample: libproc via ctypes, one
vm_stat, one sysctl, two ioreg).

Why these measures (2026-10-29 audit):
- Memory per process is the phys_footprint (Activity Monitor's Memory column, what jetsam counts), not RSS: RSS
  leaves out compressed pages and GPU (Metal) buffers. A torch MPS job showed RSS 209 MB for a 30 GB footprint,
  a kwant replay 1.3 GB RSS for 7.6 GB.
- Memory pressure is kern.memorystatus_level (the "free percentage" of memory_pressure), plus compressor,
  wired, swap; GPU memory and utilisation come from the IOAccelerator statistics; GPU time per process from the
  AGXDeviceUserClient AppUsage counters (accumulatedGPUTime).

  perf-journal.py              take one sample (launchd agent perf-journal, every 60 s)
  perf-journal.py report [H]   summary of the last H hours (default 24)
  perf-journal.py now          one sample printed, nothing written

Journal: ~/Library/Logs/macos-config/perf/YYYY-MM-DD.jsonl, 8 days kept (about 2 MB a day)."""
import ctypes, ctypes.util, datetime, glob, json, os, re, subprocess, sys, time

DIR = os.environ.get("PERF_JOURNAL_DIR") or os.path.expanduser("~/Library/Logs/macos-config/perf")
STATE = os.path.join(DIR, ".state.json")  # previous cumulative CPU/GPU times, for the per-minute deltas
KEEP_DAYS = 8
TOP = 12

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)


class RusageV2(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size", "resident_size",
        "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user_time", "child_system_time",
        "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins", "child_elapsed_abstime",
        "diskio_bytesread", "diskio_byteswritten")]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_tb = Timebase()
libc.mach_timebase_info(ctypes.byref(_tb))
TICK_NS = _tb.numer / _tb.denom  # rusage times are mach ticks (125/3 ns on Apple silicon)


def pids():
    n = libproc.proc_listallpids(None, 0)
    buf = (ctypes.c_int * (n + 64))()
    n = libproc.proc_listallpids(buf, ctypes.sizeof(buf))
    return [p for p in buf[:n] if p > 0]


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
    """argv of a process (KERN_PROCARGS2), to tell apart the pythons, nodes and rubys."""
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


def short(pid, fallback):
    """'python3.12 kwant rejouer_kwant.py' rather than a 300-character command line."""
    words = args(pid).split()
    if not words:
        return fallback
    base = os.path.basename(words[0])
    rest = [w for w in words[1:] if not w.startswith("-")]
    script = next((w for w in rest if re.search(r"\.(py|mjs|cjs|js|ts|rb)$", w) or "/exe/" in w), "")
    if script:
        path = script if script.startswith("/") else os.path.join(cwd(pid), script)
        project = re.search(r"/(?:dev|ai|src)/(?:open-source/)?([^/]+)", path)
        return f"{base} {project.group(1) + ' ' if project else ''}{os.path.basename(script)}"
    return fallback


def processes():
    out = {}
    ru = RusageV2()
    for pid in pids():
        if libproc.proc_pid_rusage(pid, 2, ctypes.byref(ru)) != 0:
            continue
        out[pid] = (ru.phys_footprint, (ru.user_time + ru.system_time) * TICK_NS / 1e9, ru.proc_start_abstime)
    return out


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout


def gpu():
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


def memory():
    vm = run("/usr/bin/vm_stat")
    page = int(re.search(r"page size of (\d+)", vm).group(1))
    p = {m.group(1): int(m.group(2)) for m in re.finditer(r"^(.+?):\s+(\d+)\.", vm, re.M)}
    gb = lambda k: round(p.get(k, 0) * page / 1e9, 2)
    sc = run("/usr/sbin/sysctl", "-n", "kern.memorystatus_level", "vm.swapusage", "vm.loadavg").splitlines()
    used = re.search(r"used = ([\d.]+)M", sc[1])
    return {"free_pct": int(sc[0]), "wired_gb": gb("Pages wired down"), "compressor_gb": gb("Pages occupied by compressor"),
            "compressed_gb": gb("Pages stored in compressor"), "active_gb": gb("Pages active"),
            "inactive_gb": gb("Pages inactive"), "free_gb": gb("Pages free"),
            "swap_gb": round(float(used.group(1)) / 1024, 2) if used else None,
            "load": [float(x) for x in sc[2].strip("{} ").split()[:3]],
            "_counters": {k: p.get(k, 0) for k in ("Compressions", "Decompressions", "Swapins", "Swapouts")}}


class _Host:
    count = ctypes.c_uint32()
    info = ctypes.POINTER(ctypes.c_int32)()
    n = ctypes.c_uint32()


def cpu_ticks():
    """Whole-machine user/system/idle ticks (host_processor_info). kernel_task (pid 0) is not readable without
    root; the system share carries its work, memory compression included."""
    h = _Host()
    libc.host_processor_info(libc.mach_host_self(), 2, ctypes.byref(h.count), ctypes.byref(h.info), ctypes.byref(h.n))
    t = [0, 0, 0, 0]  # CPU_STATE_USER, SYSTEM, IDLE, NICE
    for i in range(h.count.value * 4):
        t[i % 4] += h.info[i]
    libc.vm_deallocate(ctypes.c_uint.in_dll(libc, "mach_task_self_"), ctypes.cast(h.info, ctypes.c_void_p), ctypes.c_size_t(h.n.value * 4))
    return t


def cpu_split(ticks, before):
    """Machine CPU over the last minute, in % of all cores: user (nice included), system, idle."""
    if not before:
        return {}
    d = [a - b for a, b in zip(ticks, before)]
    total = sum(d) or 1
    return {"cpu_user": round((d[0] + d[3]) * 100 / total, 1), "cpu_sys": round(d[1] * 100 / total, 1)}


def sample():
    now = time.time()
    try:
        prev = json.load(open(STATE))
    except (OSError, ValueError):
        prev = {}
    dt = now - prev.get("t", 0)
    fresh = 20 < dt < 600  # deltas only between consecutive samples
    procs, (g, gpu_pid), mem, ticks = processes(), gpu(), memory(), cpu_ticks()
    pcpu, pgpu = prev.get("cpu", {}), prev.get("gpu", {})
    rows = []
    for pid, (fp, cpu, start) in procs.items():
        k = f"{pid}:{start}"  # a pid reused by another process starts from zero
        c = (cpu - pcpu[k]) / dt * 100 if fresh and k in pcpu else None
        gt = gpu_pid.get(pid)
        gp = (gt - pgpu[str(pid)]) / (dt * 1e9) * 100 if fresh and gt is not None and str(pid) in pgpu else None
        rows.append((pid, fp, c, gp))
    keep = {r[0] for r in sorted(rows, key=lambda r: -r[1])[:TOP]}
    keep |= {r[0] for r in sorted(rows, key=lambda r: -(r[2] or 0))[:TOP] if (r[2] or 0) >= 5}
    keep |= {r[0] for r in rows if (r[3] or 0) >= 2}
    top = []
    for pid, fp, c, gp in sorted(rows, key=lambda r: -r[1]):
        if pid in keep:
            n = name(pid)
            top.append({"pid": pid, "name": short(pid, n), "mem_gb": round(fp / 1e9, 2),
                        "cpu": None if c is None else round(c, 1), "gpu": None if gp is None else round(gp, 1)})
    counters = mem.pop("_counters")
    pc = prev.get("counters", {})
    rates = {k.lower() + "_s": round((v - pc[k]) / dt) for k, v in counters.items() if fresh and k in pc}
    rec = {"t": datetime.datetime.fromtimestamp(now).isoformat(timespec="seconds"), **mem, "gpu": g, **rates,
           **cpu_split(ticks, prev.get("ticks") if fresh else None),
           "procs": len(procs), "top": top}
    state = {"t": now, "ticks": ticks, "counters": counters,
             "cpu": {f"{p}:{s}": c for p, (_, c, s) in procs.items()}, "gpu": {str(p): v for p, v in gpu_pid.items()}}
    return rec, state


def write(rec, state):
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    with open(os.path.join(DIR, rec["t"][:10] + ".jsonl"), "a") as f:
        f.write(json.dumps(rec, separators=(",", ":")) + "\n")
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE)
    limit = (datetime.date.today() - datetime.timedelta(days=KEEP_DAYS)).isoformat()
    for old in glob.glob(os.path.join(DIR, "*.jsonl")):
        if os.path.basename(old)[:10] < limit:
            os.remove(old)


def report(hours):
    since = (datetime.datetime.now() - datetime.timedelta(hours=hours)).isoformat(timespec="seconds")
    recs = []
    for path in sorted(glob.glob(os.path.join(DIR, "*.jsonl"))):
        with open(path) as f:
            recs += [r for r in map(json.loads, f) if r["t"] >= since]
    if not recs:
        sys.exit(f"no sample in the last {hours} h ({DIR})")
    avg = lambda xs: sum(xs) / len(xs) if xs else float("nan")
    col = lambda k: [r[k] for r in recs if r.get(k) is not None]
    print(f"{len(recs)} samples, {recs[0]['t']} → {recs[-1]['t']}")
    fp = col("free_pct")
    print(f"memory free (kernel): avg {avg(fp):.0f} %, min {min(fp)} %; below 15 %: "
          f"{sum(x < 15 for x in fp) * 100 // len(fp)} % of the time")
    for k, label in (("wired_gb", "wired"), ("compressor_gb", "compressor"), ("swap_gb", "swap")):
        xs = col(k)
        print(f"{label}: avg {avg(xs):.1f} GB, max {max(xs):.1f} GB")
    print(f"compressions/s avg {avg(col('compressions_s')):.0f}, swapins/s avg {avg(col('swapins_s')):.0f}, "
          f"swapouts/s avg {avg(col('swapouts_s')):.0f}")
    print(f"CPU (all cores): user avg {avg(col('cpu_user')):.0f} %, system avg {avg(col('cpu_sys')):.0f} % "
          f"(kernel work: memory compression, I/O)")
    print(f"load avg {avg([r['load'][0] for r in recs]):.1f} (18 cores); GPU util avg "
          f"{avg([r['gpu']['util'] for r in recs if r['gpu']['util'] is not None]):.0f} %, GPU memory max "
          f"{max(r['gpu']['inuse_gb'] for r in recs):.1f} GB")
    agg = {}
    for r in recs:
        for p in r["top"]:
            a = agg.setdefault(p["name"], {"mem": 0.0, "max": 0.0, "cpu": 0.0, "gpu": 0.0})
            a["mem"] += p["mem_gb"]; a["max"] = max(a["max"], p["mem_gb"])
            a["cpu"] += p["cpu"] or 0; a["gpu"] += p["gpu"] or 0
    n = len(recs)
    for key, title, unit in (("mem", "memory (GB, average over the period, same-named processes added up)", "GB"), ("cpu", "CPU (% of a core)", "%"),
                             ("gpu", "GPU time (%)", "%")):
        print(f"\ntop {title}:")
        for nm, a in sorted(agg.items(), key=lambda kv: -kv[1][key])[:10]:
            if a[key] / n >= 0.05:
                extra = f"  (max {a['max']:.1f} GB)" if key == "mem" else ""
                print(f"  {a[key] / n:7.2f} {unit}  {nm}{extra}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sample"
    if cmd == "report":
        report(float(sys.argv[2]) if len(sys.argv) > 2 else 24)
    elif cmd == "now":
        print(json.dumps(sample()[0], indent=1))
    else:
        write(*sample())

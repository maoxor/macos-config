#!/usr/bin/env python3
"""jobgate: run heavy jobs (ML, data replays, parallel linters) at full power without letting them thrash the Mac.

It does not cap anything. A job starts as soon as the memory it needs is really free, and uses all it wants;
concurrency is reduced only when it becomes counter-productive, i.e. when the machine starts thrashing (the
2026-10-29 measure: 31 % of all cores spent compressing and paging, 240 MB/s of swap-ins; the 2026-10-12 panic:
compressor segments 100 %, 70 swapfiles). Shared by every Claude Code session and terminal; no daemon: each
`jobgate run` supervises its own job and they coordinate through ~/.local/state/jobgate/.

  jobgate run [--mem GB] [--gpu] [--name KEY] [--no-pause] -- CMD...   wait for room, run, supervise, record
  jobgate workers --per-worker GB [--max N]   worker count that fits now (e.g. PARALLEL_PROCESSOR_COUNT)
  jobgate status                              headroom, pressure, running / waiting / paused jobs
  jobgate history [KEY]                       past runs: wait, duration, peak memory, pauses
  jobgate bench --levels 1,2,4,8 -- CMD {i}   throughput at each concurrency, Universal Scalability Law fit
  jobgate self-test                           pure-logic tests (run by scripts/check.sh)

Admission: need <= headroom, where headroom = kernel free memory - what admitted jobs will still grow into
(their need minus their current footprint) - a system reserve; FIFO, a younger job may overtake only while
older waiters have waited under 10 min. Need = --mem, else the 95th percentile of this job's past peaks
(x1.1), else 4 GB until it is learnt. A --gpu job waits too while the GPU is already busy (>= 70 % over the last
samples): two jobs on a saturated GPU only share it, they do not finish sooner.
PyTorch MPS: a --gpu job gets PYTORCH_MPS_HIGH_WATERMARK_RATIO sized to the memory really free when it starts
(not a fixed cap; the default 1.7 x recommendedMaxWorkingSetSize lets one job ask for ~95 GB on 64 GB), unless
the caller set it. Adaptive throttle: while the machine thrashes (pressure warn/critical, or swap-ins and kernel
CPU both high, for 10 s) the youngest pausable job is paused (SIGSTOP; GPU jobs are not pausable by default:
their memory is wired and pausing frees nothing); paused jobs resume oldest first once it is calm for 20 s. Last
resort (the legacy watchdog's role): memory critical for 20 s → the youngest job is stopped, exit 75.
Compatible with the projects' heavy.py / lourd.py lock (~/.cache/gpu-lourd.lock): a --gpu job waits while a
live legacy job holds it and holds it while it runs, so legacy copies keep working."""
import fcntl, json, math, os, re, signal, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import macstat  # noqa: E402

STATE = os.path.expanduser(os.environ.get("JOBGATE_STATE") or "~/.local/state/jobgate")
JOBS = os.path.join(STATE, "jobs")
HISTORY = os.path.join(STATE, "history.jsonl")
THROTTLE = os.path.join(STATE, "throttle.json")
LEGACY = os.path.expanduser(os.environ.get("JOBGATE_LEGACY_DIR") or "~/.cache")  # tests use their own
LEGACY_LOCK = os.path.join(LEGACY, "gpu-lourd.lock")
LEGACY_QUEUE = os.path.join(LEGACY, "gpu-lourd.queue")
FORCE_THRASH = os.environ.get("JOBGATE_TEST_THRASH")  # tests: thrashing while this file exists
FORCE_CRITICAL = os.environ.get("JOBGATE_TEST_CRITICAL")  # tests: memory critical while this file exists
GB = 1e9
RESERVE = max(4 * GB, 0.08 * macstat.RAM)  # left to macOS, apps and windows
DEFAULT_NEED = 4 * GB
TICK = 2.0


# ---------- pure decisions (tested by self-test) ----------

def headroom(free_bytes, admitted, reserve=RESERVE):
    """free_bytes: kernel free memory; admitted: [(need, current_footprint)] of the jobs already started."""
    return free_bytes - sum(max(0.0, need - cur) for need, cur in admitted) - reserve


def may_start(me, waiting, now, room, need, gpu_busy=False, gpu=False):
    """me / waiting: {'pid', 'queued'}. FIFO with bounded overtaking."""
    if need > room or (gpu and gpu_busy):
        return False
    older = [w for w in waiting if (w["queued"], w["pid"]) < (me["queued"], me["pid"])]
    return all(now - w["queued"] < 600 for w in older)


def learnt_need(peaks):
    if not peaks:
        return None
    s = sorted(peaks)
    return s[min(len(s) - 1, int(math.ceil(0.95 * len(s))) - 1)] * 1.1


def mps_ratios(room_bytes, recommended):
    """Watermarks giving a PyTorch MPS job all the memory free at its start: high = room / recommended working set
    (bounded by PyTorch's own default 1.7, at least 0.25), low = 0.8 x high (PyTorch refuses low > high: 'invalid
    low watermark ratio 1.4' when only the high one is lowered)."""
    if not recommended:
        return None
    high = max(0.25, min(1.7, room_bytes / recommended))
    return round(high, 3), round(high * 0.8, 3)


def thrashing(level, swapins_s, sys_pct):
    """level: kern.memorystatus_vm_pressure_level (1 normal, 2 warn, 4 critical); swapins_s: 16 KB pages/s."""
    if FORCE_THRASH and os.path.exists(FORCE_THRASH):
        return True
    return level >= 2 or (swapins_s > 2000 and sys_pct > 15)


def critical(level, free_bytes, ram):
    """Last resort, the case of the 2026-10-12 panic: kernel pressure critical, or under 3 % of memory left."""
    if FORCE_CRITICAL and os.path.exists(FORCE_CRITICAL):
        return True
    return level >= 4 or free_bytes < 0.03 * ram


def youngest(jobs):
    return max(jobs, key=lambda j: (j["started"], j["pid"])) if jobs else None


def pause_candidate(running):
    """The youngest running pausable job, never the last running one (pausing everything does no work)."""
    active = [j for j in running if j["state"] == "running"]
    return youngest([j for j in active if j["pausable"]]) if len(active) >= 2 else None


def oldest(jobs):
    return min(jobs, key=lambda j: (j["started"], j["pid"])) if jobs else None


def usl_fit(points):
    """points: [(N, throughput)]. Fit X(N) = l*N / (1 + a(N-1) + b*N(N-1)) (Gunther); returns a, b, l, N*."""
    best = None
    for ia in range(0, 101):
        a = ia / 100
        for ib in range(0, 201):
            b = ib / 2000
            shape = [n / (1 + a * (n - 1) + b * n * (n - 1)) for n, _ in points]
            lam = sum(s * x for s, (_, x) in zip(shape, points)) / sum(s * s for s in shape)
            err = sum((lam * s - x) ** 2 for s, (_, x) in zip(shape, points))
            if best is None or err < best[0]:
                best = (err, a, b, lam)
    _, a, b, lam = best
    peak = math.sqrt((1 - a) / b) if b > 0 else float("inf")
    return a, b, lam, peak


# ---------- shared state ----------

def write_json(path, data):
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def jobs():
    out = []
    for n in os.listdir(JOBS) if os.path.isdir(JOBS) else []:
        if not n.endswith(".json"):
            continue
        j = read_json(os.path.join(JOBS, n))
        if j and macstat.alive(j["pid"]):
            out.append(j)
        elif j:
            try:
                os.remove(os.path.join(JOBS, n))
            except OSError:
                pass
    return out


def legacy_holder():
    h = read_json(LEGACY_LOCK)
    if h is None and os.path.exists(LEGACY_LOCK):
        return {"pid": -1}
    if h and not macstat.alive(int(h.get("pid", -1))):
        try:  # a dead holder's lock is stale (heavy.py removes it the same way)
            os.remove(LEGACY_LOCK)
        except OSError:
            pass
        return None
    return h


def legacy_tickets_before(t):
    try:
        names = sorted(os.listdir(LEGACY_QUEUE))
    except OSError:
        return 0
    n = 0
    for name in names:
        try:
            ns, pid = name[:-5].split("-")
            if int(ns) / 1e9 < t and macstat.alive(int(pid)):
                n += 1
        except ValueError:
            continue
    return n


class Sampler:
    """Swap-in rate and kernel CPU share between two calls."""

    def __init__(self):
        self.prev = None

    def __call__(self):
        page, p = macstat.vm()
        now, ticks = time.time(), macstat.cpu_ticks()
        cur = (now, p.get("Swapins", 0), ticks)
        swapins_s, sys_pct = 0.0, 0.0
        if self.prev:
            dt = max(0.1, now - self.prev[0])
            swapins_s = (cur[1] - self.prev[1]) / dt
            d = [a - b for a, b in zip(ticks, self.prev[2])]
            sys_pct = d[1] * 100 / (sum(d) or 1)
        self.prev = cur
        free = macstat.kernel_free_pct() / 100 * macstat.RAM
        return {"free": free, "level": macstat.pressure_level(), "swapins_s": swapins_s, "sys_pct": sys_pct}


def job_key(cmd):
    """'proj/replay.py' for 'python -I scripts/replay.py …' run in ~/dev/proj."""
    script = next((w for w in cmd[1:] if re.search(r"\.(py|mjs|cjs|js|ts|rb|sh)$", w) or "/exe/" in w), cmd[0])
    path = script if script.startswith("/") else os.path.join(os.getcwd(), script)
    project = re.search(r"/(?:dev|ai|src)/(?:open-source/)?([^/]+)", path)
    return f"{project.group(1) + '/' if project else ''}{os.path.basename(script)}"


def history(key=None):
    out = []
    try:
        with open(HISTORY) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if key is None or r.get("key") == key:
                    out.append(r)
    except OSError:
        pass
    return out


def log(msg):
    print(f"[jobgate {time.strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


# ---------- commands ----------

def cmd_run(argv):
    opts, cmd = parse(argv, {"--mem": float, "--name": str}, {"--gpu", "--no-pause"})
    if not cmd:
        sys.exit("jobgate run [--mem GB] [--gpu] [--name KEY] [--no-pause] -- CMD...")
    os.makedirs(JOBS, exist_ok=True)
    key = opts.get("--name") or job_key(cmd)
    gpu = "--gpu" in opts
    learnt = learnt_need([r["peak_gb"] * GB for r in history(key)[-20:] if r.get("exit") == 0])
    need = opts["--mem"] * GB if "--mem" in opts else (learnt or DEFAULT_NEED)
    me = {"pid": os.getpid(), "key": key, "need": need, "gpu": gpu, "pausable": not gpu and "--no-pause" not in opts,
          "queued": time.time(), "state": "waiting", "started": None, "cmd": " ".join(cmd)[:200]}
    mine = os.path.join(JOBS, f"{os.getpid()}.json")
    write_json(mine, me)
    sample = Sampler()
    gpu_hist = []
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    child, legacy_mine = None, False
    try:
        sample()
        last_note, first = time.time() - 290, True  # first note after 10 s of waiting, then every 5 min
        while True:  # ---- admission
            time.sleep(0.5 if first else TICK)
            first = False
            m = sample()
            others = jobs()
            admitted = [(j["need"], macstat.tree_footprint(j["pid"])) for j in others if j["state"] != "waiting"]
            holder = legacy_holder()
            if holder and holder.get("pid") != os.getpid() and not holder.get("jobgate"):
                admitted.append((float(holder.get("go", 0)) * GB, macstat.tree_footprint(int(holder["pid"]))))
            room = headroom(m["free"], admitted)
            if gpu:
                gpu_hist = (gpu_hist + [macstat.gpu_util() or 0])[-5:]
            # Busy GPU = saturated by a job we coordinate (gated or legacy holder): waiting for an outside user of
            # the GPU (a WebGL test page) could last forever, and time-sharing with it is harmless.
            gpu_jobs = any(j["gpu"] for j in others if j["state"] != "waiting") or bool(holder and not holder.get("jobgate"))
            gpu_busy = gpu_jobs and (len(gpu_hist) < 3 or min(gpu_hist) >= 70)  # 3 samples before deciding
            blocked = None
            if thrashing(m["level"], m["swapins_s"], m["sys_pct"]):
                blocked = "the machine is thrashing"
            elif gpu and holder and not holder.get("jobgate"):
                blocked = f"legacy lock held by {holder.get('session')} pid {holder.get('pid')}"
            elif gpu and legacy_tickets_before(me["queued"]):
                blocked = "legacy heavy.py jobs queued before this one"
            waiting = [j for j in others if j["state"] == "waiting"]
            if not blocked and may_start(me, waiting, time.time(), room, need, gpu_busy, gpu):
                # Decide again under the admission lock and mark this job running before releasing it: two waiters
                # seeing the same free room in the same tick would otherwise both start.
                admission = open(os.path.join(STATE, "admission.lock"), "w")
                fcntl.flock(admission, fcntl.LOCK_EX)
                others = jobs()
                admitted = [(j["need"], macstat.tree_footprint(j["pid"])) for j in others if j["state"] != "waiting"]
                if holder and holder.get("pid") != os.getpid() and not holder.get("jobgate"):
                    admitted.append((float(holder.get("go", 0)) * GB, macstat.tree_footprint(int(holder["pid"]))))
                room = headroom(m["free"], admitted)
                if may_start(me, [j for j in others if j["state"] == "waiting"], time.time(), room, need):
                    me.update(state="starting", started=time.time())
                    write_json(mine, me)
                    admission.close()
                    break
                admission.close()
            if time.time() - last_note > 300:
                last_note = time.time()
                log(f"{key} waits: needs {need / GB:.1f} GB, room {room / GB:.1f} GB"
                    + (f"; {blocked}" if blocked else "") + ("; GPU busy" if gpu and gpu_busy and len(gpu_hist) >= 3 else ""))
        env = dict(os.environ)
        if gpu:
            if not holder:
                try:
                    fd = os.open(LEGACY_LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                    with os.fdopen(fd, "w") as f:
                        json.dump({"session": f"jobgate {key}", "pid": os.getpid(), "jobgate": True,
                                   "debut": time.strftime("%Y-%m-%dT%H:%M:%S"), "go": round(need / GB, 1),
                                   "commande": me["cmd"]}, f)
                    legacy_mine = True
                except OSError:
                    pass
            r = mps_ratios(room + need, macstat.metal_recommended_max())
            if r and "PYTORCH_MPS_HIGH_WATERMARK_RATIO" not in env:
                env["PYTORCH_MPS_HIGH_WATERMARK_RATIO"], env["PYTORCH_MPS_LOW_WATERMARK_RATIO"] = map(str, r)
        t0 = time.time()
        me.update(state="running", started=t0)
        write_json(mine, me)
        log(f"{key} starts (need {need / GB:.1f} GB{', learnt' if learnt and '--mem' not in opts else ''}, "
            f"room {room / GB:.1f} GB, waited {t0 - me['queued']:.0f} s)")
        child = subprocess.Popen(cmd, env=env)
        me["child"] = child.pid
        write_json(mine, me)
        peak, paused_s, pauses, bad, calm, crit, stopped = 0, 0.0, 0, 0.0, 0.0, 0.0, False
        while child.poll() is None:  # ---- supervision
            time.sleep(TICK)
            m = sample()
            peak = max(peak, macstat.tree_footprint(child.pid))
            if me["gpu"] and not legacy_mine and not legacy_holder():
                try:  # a jobgate GPU job that ended released the lock: hold it for the legacy copies
                    fd = os.open(LEGACY_LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                    with os.fdopen(fd, "w") as f:
                        json.dump({"session": f"jobgate {key}", "pid": os.getpid(), "jobgate": True, "go": round(need / GB, 1)}, f)
                    legacy_mine = True
                except OSError:
                    pass
            bad, calm = (bad + TICK, 0.0) if thrashing(m["level"], m["swapins_s"], m["sys_pct"]) else (0.0, calm + TICK)
            running = [j for j in jobs() if j["state"] in ("running", "paused")]
            thr = read_json(THROTTLE, {"t": 0})
            crit = crit + TICK if critical(m["level"], m["free"], macstat.RAM) else 0.0
            if crit >= 20 and time.time() - thr["t"] > 15 and (youngest(running) or {}).get("pid") == os.getpid():
                # Pausing could not prevent it: stop the youngest job before the Mac stalls (exit 75 = retry later).
                write_json(THROTTLE, {"t": time.time(), "by": os.getpid(), "action": "stop"})
                log(f"{key} stopped: memory critical for {crit:.0f} s (pressure {m['level']}, "
                    f"{m['free'] / GB:.1f} GB free); exit 75, run it again later")
                stop_tree(child)
                stopped = True
                break
            if me["state"] == "running" and bad >= 10 and time.time() - thr["t"] > 15:
                cand = pause_candidate(running)
                if cand and cand["pid"] == os.getpid():
                    for p in macstat.tree(child.pid):
                        os.kill(p, signal.SIGSTOP)
                    me.update(state="paused", paused_at=time.time())
                    pauses += 1
                    write_json(mine, me)
                    write_json(THROTTLE, {"t": time.time(), "by": os.getpid(), "action": "pause"})
                    log(f"{key} paused: machine thrashing (pressure {m['level']}, {m['swapins_s']:.0f} swap-ins/s, "
                        f"kernel {m['sys_pct']:.0f} % CPU)")
            elif me["state"] == "paused" and calm >= 20 and time.time() - thr["t"] > 20:
                cand = oldest([j for j in running if j["state"] == "paused"])
                if cand and cand["pid"] == os.getpid():
                    for p in macstat.tree(child.pid):
                        os.kill(p, signal.SIGCONT)
                    paused_s += time.time() - me.pop("paused_at")
                    me["state"] = "running"
                    write_json(mine, me)
                    write_json(THROTTLE, {"t": time.time(), "by": os.getpid(), "action": "resume"})
                    log(f"{key} resumed after {paused_s:.0f} s paused in total")
        code = 75 if stopped else child.returncode
        rec = {"t": time.strftime("%Y-%m-%dT%H:%M:%S"), "key": key, "need_gb": round(need / GB, 2),
               "peak_gb": round(peak / GB, 2), "wait_s": round(t0 - me["queued"]), "run_s": round(time.time() - t0),
               "paused_s": round(paused_s), "pauses": pauses, "gpu": gpu, "exit": code, "stopped": stopped}
        with open(HISTORY, "a") as f:
            f.write(json.dumps(rec) + "\n")
        log(f"{key} done: exit {code}, {rec['run_s']} s, peak {rec['peak_gb']} GB")
        sys.exit(code if code >= 0 else 128 - code)
    finally:
        if child and child.poll() is None:  # killed while running: take the job down with us
            stop_tree(child)
        if legacy_mine and (read_json(LEGACY_LOCK) or {}).get("pid") == os.getpid():
            os.remove(LEGACY_LOCK)
        try:
            os.remove(mine)
        except OSError:
            pass


def stop_tree(child, grace=20):
    """SIGCONT (a paused job cannot exit) then SIGTERM to the whole tree; SIGKILL what is left after grace s."""
    procs = macstat.tree(child.pid)
    for sig in (signal.SIGCONT, signal.SIGTERM):
        for p in procs:
            try:
                os.kill(p, sig)
            except OSError:
                pass
    try:
        child.wait(grace)
    except subprocess.TimeoutExpired:
        pass
    for p in procs:
        if macstat.alive(p):
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
    child.poll()


def cmd_workers(argv):
    opts, _ = parse(argv, {"--per-worker": float, "--max": int}, set())
    per = opts.get("--per-worker", 1.0) * GB
    s = Sampler()
    m = s()
    admitted = [(j["need"], macstat.tree_footprint(j["pid"])) for j in jobs() if j["state"] != "waiting"]
    room = headroom(m["free"], admitted)
    n = max(1, min(opts.get("--max", macstat.NCPU), macstat.NCPU, int(room // per)))
    print(n)


def cmd_status(_):
    s = Sampler()
    s()
    time.sleep(1)
    m = s()
    js = jobs()
    admitted = [(j["need"], macstat.tree_footprint(j["pid"])) for j in js if j["state"] != "waiting"]
    print(f"memory free (kernel) {m['free'] / GB:.1f} GB of {macstat.RAM / GB:.0f}; pressure level {m['level']}; "
          f"swap-ins {m['swapins_s']:.0f}/s; kernel CPU {m['sys_pct']:.0f} %; "
          f"thrashing: {'yes' if thrashing(m['level'], m['swapins_s'], m['sys_pct']) else 'no'}")
    print(f"room for a new job: {headroom(m['free'], admitted) / GB:.1f} GB (system reserve {RESERVE / GB:.1f} GB)")
    h = legacy_holder()
    if h:
        print(f"legacy lock: {h.get('session')} pid {h.get('pid')} ({h.get('go')} GB)")
    for j in sorted(js, key=lambda j: j["queued"]):
        fp = macstat.tree_footprint(j["pid"]) / GB
        print(f"  {j['state']:8} {j['key']:40} need {j['need'] / GB:5.1f} GB  now {fp:5.1f} GB"
              f"{'  gpu' if j['gpu'] else ''}  pid {j['pid']}")


def cmd_history(argv):
    for r in history(argv[0] if argv else None)[-30:]:
        print(f"{r['t']}  {r['key']:40} exit {r['exit']:>3}  wait {r['wait_s']:>5} s  run {r['run_s']:>6} s  "
              f"peak {r['peak_gb']:5.1f} GB  paused {r['paused_s']} s")


def cmd_bench(argv):
    """Run CMD at each concurrency level N (N copies at once, {i} = copy index); throughput = N / wall time."""
    opts, cmd = parse(argv, {"--levels": str}, set())
    levels = [int(x) for x in opts.get("--levels", "1,2,4,8").split(",")]
    points = []
    for n in levels:
        t0 = time.time()
        procs = [subprocess.Popen([w.replace("{i}", str(i)) for w in cmd]) for i in range(n)]
        codes = [p.wait() for p in procs]
        wall = time.time() - t0
        points.append((n, n / wall))
        print(f"N={n:3}  wall {wall:8.2f} s  throughput {n / wall:8.4f} jobs/s  exits {set(codes)}", flush=True)
    if len(points) >= 3:
        a, b, lam, peak = usl_fit(points)
        print(f"USL: contention a={a:.3f}, coherency b={b:.4f}, X(1)={lam:.4f}/s; throughput peaks at N*={peak:.1f}")


def cmd_self_test(_):
    ok = True

    def check(cond, what):
        nonlocal ok
        print(f"  {'ok  ' if cond else 'FAIL'}  {what}")
        ok &= bool(cond)

    check(headroom(40 * GB, [(30 * GB, 10 * GB)], 5 * GB) == 15 * GB, "headroom counts what admitted jobs will grow into")
    check(headroom(40 * GB, [(10 * GB, 30 * GB)], 5 * GB) == 35 * GB, "a job above its need reserves nothing more")
    me, older = {"pid": 2, "queued": 100}, {"pid": 1, "queued": 50}
    check(may_start(me, [older, me], 200, 10 * GB, 5 * GB), "a fitting job may overtake a young waiter")
    check(not may_start(me, [older, me], 700, 10 * GB, 5 * GB), "no overtaking a waiter older than 10 min")
    check(not may_start(me, [me], 200, 4 * GB, 5 * GB), "no start without room")
    check(not may_start(me, [me], 200, 40 * GB, 5 * GB, gpu_busy=True, gpu=True), "a GPU job waits for a busy GPU")
    check(may_start(me, [me], 200, 40 * GB, 5 * GB, gpu_busy=True, gpu=False), "a CPU job ignores the GPU")
    check(mps_ratios(50 * GB, 55.66 * GB) == (0.898, 0.719), "MPS watermark = free room / recommended working set")
    check(mps_ratios(200 * GB, 55.66 * GB) == (1.7, 1.36), "never above PyTorch's own default 1.7")
    h, lo = mps_ratios(5 * GB, 55.66 * GB)
    check(h == 0.25 and lo < h, "low watermark stays below high")
    check(abs(learnt_need([1 * GB, 2 * GB, 10 * GB]) - 11 * GB) < 1, "learnt need = p95 of past peaks x 1.1")
    check(learnt_need([]) is None, "no history, no learnt need")
    check(thrashing(2, 0, 0) and thrashing(1, 5000, 30) and not thrashing(1, 5000, 5) and not thrashing(1, 100, 40),
          "thrashing = pressure warn, or swap-ins and kernel CPU together")
    js = [{"pid": 1, "started": 10}, {"pid": 2, "started": 20}]
    check(youngest(js)["pid"] == 2 and oldest(js)["pid"] == 1, "pause the youngest, resume the oldest")
    run = [dict(j, state="running", pausable=True) for j in js]
    check(pause_candidate(run)["pid"] == 2, "the youngest running job is paused first")
    check(pause_candidate([run[0], dict(run[1], state="paused")]) is None, "the last running job is never paused")
    check(pause_candidate([run[0], dict(run[1], pausable=False)])["pid"] == 1, "a non-pausable job is skipped")
    check(critical(4, 30 * GB, 64 * GB) and critical(1, 1 * GB, 64 * GB) and not critical(2, 10 * GB, 64 * GB),
          "last resort only when critical or under 3 % free")
    pts = [(n, 0.5 * n / (1 + 0.05 * (n - 1) + 0.002 * n * (n - 1))) for n in (1, 2, 4, 8, 16, 32)]
    a, b, lam, peak = usl_fit(pts)
    check(abs(a - 0.05) < 0.011 and abs(b - 0.002) < 0.0006 and abs(peak - 21.8) < 2, f"USL fit (N* {peak:.1f})")
    check(job_key(["python", "/x/dev/proj/scripts/replay.py", "--a"]) == "proj/replay.py", "job key")
    sys.exit(0 if ok else 1)


def parse(argv, valued, flags):
    opts, i = {}, 0
    while i < len(argv):
        a = argv[i]
        if a == "--":
            return opts, argv[i + 1:]
        if a in valued:
            opts[a] = valued[a](argv[i + 1])
            i += 2
        elif a in flags:
            opts[a] = True
            i += 1
        else:
            return opts, argv[i:]
    return opts, []


if __name__ == "__main__":
    cmds = {"run": cmd_run, "workers": cmd_workers, "status": cmd_status, "history": cmd_history,
            "bench": cmd_bench, "self-test": cmd_self_test}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(__doc__)
    cmds[sys.argv[1]](sys.argv[2:])

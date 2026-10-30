// Memory guard: stops a job before macOS runs out of compressor store and the Mac panics (docs/bugs.md B21,
// docs/performance.md §4). Both panics (2026-10-12, 2026-10-30) ended at 100 % of the store, compressed data in memory
// + swap, about 101 GB here, with kern.memorystatus_level still at 41 % 30 s before: memory pressure does not see it
// coming and swap fills at up to 640 MB/s, 0.6 % a second. Every 2 s, above MEMORY_GUARD_STOP_PCT (70, a single job
// peaked at 53 %, 74 % was a minute from 95 %), stop the youngest jobgate job, else the largest command-line process.
// Apps are never stopped: then it only warns. No fork in the loop, so that it keeps running while the Mac stalls.
//   memory-guard          loop (launchd agent memory-guard)
//   memory-guard --check  what it reads and what it would stop now; stops nothing
//   memory-guard --once   one pass that may stop something (tests, with JOBGATE_STATE and MEMORY_GUARD_STOP_PCT)
import Darwin
import Foundation

let env = ProcessInfo.processInfo.environment
let stopPercent = Double(env["MEMORY_GUARD_STOP_PCT"] ?? "") ?? 70
let jobMinBytes = UInt64(env["MEMORY_GUARD_JOB_MIN_BYTES"] ?? "") ?? 4_000_000_000
let processMinBytes: UInt64 = 8_000_000_000
let tick: TimeInterval = 2
let settle: TimeInterval = 10  // a stopped job frees its memory at once: look again before stopping another
let termGrace: TimeInterval = 3
let state = env["JOBGATE_STATE"] ?? NSHomeDirectory() + "/.local/state/jobgate"

func log(_ message: String) {
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime])
    print("\(stamp) \(message)")
    fflush(stdout)
}

func sysctlValue(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
}

func storePercent() -> Double? {
    guard let limit = sysctlValue("vm.compressor.segment.limit"),
          let segment = sysctlValue("vm.compressor_segment_buffer_size"),
          let inMemory = sysctlValue("vm.compressor_bytes_used") else { return nil }
    var swap = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
    return Double(inMemory + swap.xsu_used) * 100 / Double(limit * segment)
}

func footprint(_ pid: pid_t) -> UInt64 {
    var usage = rusage_info_v2()
    let ok = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0 }
    }
    return ok ? usage.ri_phys_footprint : 0
}

func path(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
}

func userPids() -> [pid_t] {
    var pids = [pid_t](repeating: 0, count: 8192)
    let count = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    return pids.prefix(Int(count) / MemoryLayout<pid_t>.size).filter { $0 > 0 && $0 != getpid() }
}

struct Victim {
    let pid: pid_t
    let label: String
    let bytes: UInt64
}

// The youngest admitted job that holds real memory: the older ones have more work to lose.
func youngestJob() -> Victim? {
    let dir = state + "/jobs"
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    var best: (started: Double, victim: Victim)?
    for name in names where name.hasSuffix(".json") {
        guard let data = FileManager.default.contents(atPath: dir + "/" + name),
              let job = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let child = (job["child"] as? NSNumber)?.int32Value, let started = (job["started"] as? NSNumber)?.doubleValue,
              job["state"] as? String != "waiting", kill(child, 0) == 0 else { continue }
        let bytes = footprint(child)
        if bytes >= jobMinBytes, started > (best?.started ?? 0) {
            best = (started, Victim(pid: child, label: job["key"] as? String ?? "job", bytes: bytes))
        }
    }
    return best?.victim
}

// A process that jobgate does not know, never an app: "python" from a framework lives in Python.app.
func largestCommand() -> Victim? {
    var best: Victim?
    for pid in userPids() {
        let bytes = footprint(pid)
        guard bytes >= processMinBytes, bytes > best?.bytes ?? 0 else { continue }
        let file = path(pid)
        if file.isEmpty || (file.contains(".app/") && !file.contains("/Python.app/")) { continue }
        best = Victim(pid: pid, label: (file as NSString).lastPathComponent, bytes: bytes)
    }
    return best
}

func notify(_ text: String) {
    if env["MEMORY_GUARD_SILENT"] != nil { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "display notification \"\(text)\" with title \"Protection mémoire\""]
    try? process.run()
}

func stop(_ victim: Victim, _ percent: Double) {
    let gigabytes = Double(victim.bytes) / 1e9
    log(String(format: "store %.0f %%: stopping %@ (pid %d, %.1f GB)", percent, victim.label, victim.pid, gigabytes))
    notify(String(format: "Mac presque saturé : %@ arrêté (%.0f Go).", victim.label, gigabytes))
    kill(victim.pid, SIGCONT)
    kill(victim.pid, SIGTERM)
    Thread.sleep(forTimeInterval: termGrace)
    if kill(victim.pid, 0) == 0 { kill(victim.pid, SIGKILL) }
}

func pass() {
    guard let percent = storePercent(), percent >= stopPercent else { return }
    if let victim = youngestJob() ?? largestCommand() {
        stop(victim, percent)
        Thread.sleep(forTimeInterval: settle)
    } else {
        log(String(format: "store %.0f %%: nothing to stop (only apps are large)", percent))
        notify("Mac presque saturé : ferme une application lourde.")
        Thread.sleep(forTimeInterval: 60)
    }
}

switch CommandLine.arguments.dropFirst().first {
case "--check":
    print(String(format: "store %.1f %%, stops at %.0f %%", storePercent() ?? -1, stopPercent))
    let victim = youngestJob() ?? largestCommand()
    print(victim.map { String(format: "would stop %@ (pid %d, %.1f GB)", $0.label, $0.pid, Double($0.bytes) / 1e9) } ?? "nothing to stop")
case "--once":
    pass()
default:
    log("watching the compressor store, stops at \(stopPercent) %")
    while true {
        pass()
        Thread.sleep(forTimeInterval: tick)
    }
}

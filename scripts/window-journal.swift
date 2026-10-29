// Window journal: every window that shows itself over the user's work, and who opened it (2026-10-29).
// Agents' test browsers kept flashing windows (B19) that were gone before anyone could look; this records them for
// later: owner, bundle, frame, uncovered area (Ghostty is translucent, so a window behind it counts as seen), how long
// it stayed, and the process chain that launched it (pid, name, working directory: the project).
// Polls the window list every 250 ms, every 16 ms while a test browser or driver process runs (the first window of a
// launch comes ~0.5 s after its process). JSON lines in ~/Library/Logs/macos-config/windows/YYYY-MM-DD.jsonl, 7 days.
// Run: scripts/window-journal.sh (launchd agent window-journal); `scripts/window-journal.sh report [hours]` summarises.
import AppKit
import Darwin
import Foundation
import IOKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let env = ProcessInfo.processInfo.environment
let dir = env["WINDOW_JOURNAL_DIR"] ?? home + "/Library/Logs/macos-config/windows"
// pt²: below it (a 40x41 corner, a 1 pt parked edge) nobody sees a window. WINDOW_JOURNAL_MIN_AREA for tests.
let minArea = Double(env["WINDOW_JOURNAL_MIN_AREA"] ?? "") ?? 5000
let seeThrough: Set<String> = ["com.mitchellh.ghostty"]    // background-opacity < 1: what is behind shows through
let testExecutables = ["Google Chrome for Testing", "/Chromium.app/", "/ms-playwright/", "chromedriver", "geckodriver",
                       "/Nightly.app/", "/Playwright.app/", "chrome-headless-shell"]

func day(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; f.timeZone = .current; return f }()

// MARK: processes
func pidPath(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
}
func parent(_ pid: pid_t) -> pid_t {
    var info = proc_bsdinfo()
    let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    return n > 0 ? pid_t(info.pbi_ppid) : 0
}
func cwd(_ pid: pid_t) -> String {
    var info = proc_vnodepathinfo()
    let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
    guard n > 0 else { return "" }
    return withUnsafePointer(to: &info.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
}
func chain(_ pid: pid_t) -> [[String: Any]] {
    var out: [[String: Any]] = [], p = pid
    while p > 1 && out.count < 6 {
        let path = pidPath(p)
        out.append(["pid": Int(p), "exe": (path as NSString).lastPathComponent, "cwd": cwd(p)])
        p = parent(p)
    }
    return out
}
func idleSeconds() -> Double {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    defer { IOObjectRelease(service) }
    let v = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    return ((v as? NSNumber)?.doubleValue ?? 0) / 1e9
}
var isTest: [pid_t: Bool] = [:]     // a pid's executable is read once
func testProcessRunning() -> Bool {
    let n = proc_listallpids(nil, 0)
    var pids = [pid_t](repeating: 0, count: Int(n) + 64)
    let got = Int(max(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)), 0))
    var known: [pid_t: Bool] = [:], any = false
    for pid in pids.prefix(got) where pid > 0 {
        let test = isTest[pid] ?? { let path = pidPath(pid); return testExecutables.contains { path.contains($0) } }()
        known[pid] = test; any = any || test
    }
    isTest = known
    return any
}

// MARK: journal
func write(_ obj: [String: Any]) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
    let path = "\(dir)/\(day(Date())).jsonl"
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    guard let h = FileHandle(forWritingAtPath: path) else { return }
    h.seekToEndOfFile(); h.write(data); h.write("\n".data(using: .utf8)!); h.closeFile()
}
func prune() {
    let old = Date().addingTimeInterval(-7 * 86400)
    for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".jsonl") && f < day(old) {
        try? FileManager.default.removeItem(atPath: "\(dir)/\(f)")
    }
}

// MARK: watcher
struct Seen {
    let first: Date; var lastShown: Date?; var shownSince: Date?; var maxArea = 0.0; var through: Set<String> = []
    var frame: CGRect; var logged = false; var lastPresent: Date
}
var seen: [Int: Seen] = [:]
var bundles: [pid_t: String] = [:]
func bundle(_ pid: pid_t) -> String {
    if let b = bundles[pid] { return b }
    let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    bundles[pid] = b; return b
}

func scan() {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let screen = NSScreen.main?.frame else { return }
    let bounds = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
    let now = Date()
    // Frontmost app: owner of the frontmost normal window (NSWorkspace does not update without an NSApplication).
    let front = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
        .map { bundle(pid_t($0[kCGWindowOwnerPID as String] as? Int ?? 0)) } ?? ""
    var covering: [(CGRect, String)] = [], present = Set<Int>()
    for w in list {
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let pid = pid_t(w[kCGWindowOwnerPID as String] as? Int ?? 0)
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        let num = w[kCGWindowNumber as String] as? Int ?? 0
        let id = bundle(pid)
        // Only normal and floating windows hide what is behind them: the system overlays above (Notification Center's
        // full-screen window while a banner shows, menu bar, Dock) are transparent but for a small part.
        defer { if layer >= 0 && layer < 20 && alpha > 0.05 && owner != "Window Server" { covering.append((r, id)) } }
        let vis = r.intersection(bounds)
        // Normal and floating windows only: menus, the Dock, notifications and OmniWM's swipe previews (layer >= 20)
        // answer the user's own gestures.
        guard layer >= 0 && layer < 20, owner != "Window Server" else { continue }
        present.insert(num)
        // Windows already there at launch are old; a new one is watched for its first 10 s (only those are sampled),
        // whatever its size: a page born in a corner can be moved to the middle.
        var s = seen[num] ?? Seen(first: now.timeIntervalSince(start) < 1 ? .distantPast : now, frame: r, lastPresent: now)
        s.frame = r; s.lastPresent = now
        let young = now.timeIntervalSince(s.first) < 10
        // Strips (the 8 pt margin veil, a parked edge) are not screens: at least 50 pt both ways.
        let large = alpha > 0.05 && !vis.isNull && vis.width * vis.height >= minArea && min(vis.width, vis.height) >= 50
        if s.shownSince == nil && !(young && large) { seen[num] = s; continue }
        // Uncovered share of the on-screen part, sampled on a 24x24 grid against the windows in front of it.
        var shown = 0, through = Set<String>()
        for i in 0..<24 { for j in 0..<24 {
            let p = CGPoint(x: vis.minX + (Double(i) + 0.5) * vis.width / 24, y: vis.minY + (Double(j) + 0.5) * vis.height / 24)
            var hidden = false, behind: String?
            for (c, cid) in covering where c.contains(p) {
                if seeThrough.contains(cid) { behind = cid } else { hidden = true; break }
            }
            if !hidden { shown += 1; if let b = behind { through.insert(b) } }
        } }
        let area = large ? vis.width * vis.height * Double(shown) / 576 : 0
        if young && area >= minArea {
            if s.shownSince == nil { s.shownSince = now }
            s.lastShown = now; s.maxArea = max(s.maxArea, area); s.through.formUnion(through)
            if !s.logged {
                s.logged = true
                write(["t": iso.string(from: now), "event": "shown", "window": num, "owner": owner, "bundle": id,
                       "layer": layer, "frame": [Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)],
                       "area_pt2": Int(area), "screen_pct": Int(100 * area / (bounds.width * bounds.height)),
                       "through": Array(through), "front_app": front, "idle_s": Int(idleSeconds()),
                       "chain": chain(pid)])
            }
        } else if let since = s.shownSince, s.logged, let last = s.lastShown, s.maxArea > 0 {
            write(["t": iso.string(from: now), "event": "hidden", "window": num, "owner": owner,
                   "shown_ms": Int(last.timeIntervalSince(since) * 1000), "max_area_pt2": Int(s.maxArea),
                   "through": Array(s.through)])
            s.shownSince = nil; s.maxArea = 0
        }
        seen[num] = s
    }
    // A window gone from the list (closed, app hidden) is remembered for an hour: back on screen it is not new.
    for (num, var s) in seen where !present.contains(num) {
        if let since = s.shownSince, let last = s.lastShown, s.maxArea > 0 {
            write(["t": iso.string(from: now), "event": "hidden", "window": num, "shown_ms": Int(last.timeIntervalSince(since) * 1000),
                   "max_area_pt2": Int(s.maxArea), "through": Array(s.through)])
            s.shownSince = nil; s.maxArea = 0; seen[num] = s
        }
        if now.timeIntervalSince(s.lastPresent) > 3600 { seen[num] = nil }
    }
}

// CGWindowListCreate (window numbers only, no dictionaries) is marked unavailable in Swift: call it by name. Its
// array holds the raw numbers, not CFNumbers.
typealias WindowListCreate = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
let windowListCreate = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreate")
    .map { unsafeBitCast($0, to: WindowListCreate.self) }
func windowNumbers() -> Set<Int> {
    let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements]).rawValue
    guard let f = windowListCreate, let array = f(options, kCGNullWindowID)?.takeRetainedValue() else { return [] }
    return Set((0..<CFArrayGetCount(array)).map { Int(bitPattern: CFArrayGetValueAtIndex(array, $0)) })
}

// MARK: report
func report(hours: Double) {
    let since = Date().addingTimeInterval(-hours * 3600)
    var rows: [[String: Any]] = []
    for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".jsonl") && f >= day(since) {
        let text = (try? String(contentsOfFile: "\(dir)/\(f)", encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let t = (o["t"] as? String).flatMap(iso.date(from:)), t >= since else { continue }
            rows.append(o)
        }
    }
    var shownMs: [Int: Int] = [:]
    for o in rows where o["event"] as? String == "hidden" { shownMs[o["window"] as? Int ?? 0] = o["shown_ms"] as? Int }
    let shown = rows.filter { $0["event"] as? String == "shown" }
    print("Windows shown over the user's work, last \(Int(hours)) h: \(shown.count)")
    for o in shown {
        let t = (o["t"] as? String ?? "").dropFirst(11).prefix(12)
        let c = (o["chain"] as? [[String: Any]] ?? []).map { "\($0["exe"] ?? "")" }.joined(separator: "<")
        let proj = (o["chain"] as? [[String: Any]] ?? []).compactMap { $0["cwd"] as? String }.first { $0 != "/" && !$0.isEmpty } ?? ""
        let through = (o["through"] as? [String] ?? []).isEmpty ? "" : " through \((o["through"] as? [String] ?? []).joined(separator: ","))"
        let ms = shownMs[o["window"] as? Int ?? 0].map { "\($0) ms" } ?? "?"
        // The user's own: a window of the frontmost app while they were typing or clicking.
        let own = (o["bundle"] as? String) == (o["front_app"] as? String) && (o["idle_s"] as? Int ?? 99) < 2 ? " (user)" : ""
        print("\(t)  \(o["owner"] ?? "")\(own) \(o["screen_pct"] ?? 0)% of the screen, \(ms)\(through)  [\(c)] \(proj)")
    }
}

let args = CommandLine.arguments.dropFirst()
if args.first == "report" { report(hours: Double(args.dropFirst().first ?? "24") ?? 24); exit(0) }
setvbuf(stdout, nil, _IOLBF, 0)
let start = Date()
prune()
var fast = false, lastCheck = Date.distantPast, lastPrune = Date(), lastIds = Set<Int>()
func tick() {
    let now = Date()
    if now.timeIntervalSince(lastCheck) >= 0.25 { fast = testProcessRunning() || !seen.values.allSatisfy { $0.shownSince == nil }; lastCheck = now }
    if now.timeIntervalSince(lastPrune) > 86400 { prune(); lastPrune = now }
    // The window numbers alone are cheap; the full descriptions (~5 ms) are read only when a window appeared or a
    // young window is being followed.
    let ids = windowNumbers()
    if ids.isEmpty || !ids.subtracting(lastIds).isEmpty
        || seen.values.contains(where: { now.timeIntervalSince($0.first) < 10 && now.timeIntervalSince($0.lastPresent) < 1 || $0.shownSince != nil }) {
        scan()
    }
    lastIds = ids
    Timer.scheduledTimer(withTimeInterval: fast ? 0.016 : 0.25, repeats: false) { _ in tick() }
}
tick()
RunLoop.main.run()

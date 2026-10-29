// Playwright watch: patches each Playwright copy as soon as it is written (2026-10-29).
// Sessions install Playwright (npm, pip, uv, npx) and run their first test within seconds; the hourly walk of
// scripts/playwright-background-pages.py came minutes later, so those first runs still flashed (B19), and the walk
// itself cost ~5 s of CPU over 166 000 directories. FSEvents reports every file written under the roots for free;
// the two files the patch changes are handed to `playwright-background-pages.py --files`, which checks and patches.
// Run: scripts/swift-tool.sh playwright-watch <repo>/scripts/playwright-background-pages.py (agent playwright-watch).
import CoreServices
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let patcher = CommandLine.arguments.dropFirst().first ?? ""   // scripts/playwright-background-pages.py
// Same roots as the patcher. Parents that always exist are watched (the session scratchpads and the Codex runtime
// appear later), and events are filtered by prefix.
let prefixes = ["\(home)/dev/", "\(home)/src/", "\(home)/ai/", "\(home)/.npm/_npx/", "\(home)/.cache/codex-runtimes/",
                "/private/tmp/claude-\(getuid())/"]
let watched = ["\(home)/dev", "\(home)/src", "\(home)/ai", "\(home)/.npm", "\(home)/.cache", "/private/tmp"]
let suffixes = ["/lib/coreBundle.js", "/lib/server/chromium/crBrowser.js"]
setvbuf(stdout, nil, _IOLBF, 0)

var pending = Set<String>()
var flushScheduled = false
func flush() {
    flushScheduled = false
    let files = Array(pending); pending.removeAll()
    guard !files.isEmpty else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    p.arguments = ["-I", patcher, "--files"] + files
    do { try p.run(); p.waitUntilExit() } catch { FileHandle.standardError.write("playwright-watch: \(error)\n".data(using: .utf8)!) }
}

let callback: FSEventStreamCallback = { _, _, count, paths, _, _ in
    let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
    for path in list.prefix(count) where suffixes.contains(where: path.hasSuffix) && prefixes.contains(where: path.hasPrefix) {
        pending.insert(path)
    }
    // Writes come in bursts (an install, then the patch's own write): one patcher run 0.25 s after the last.
    if !pending.isEmpty && !flushScheduled {
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { flush() }
    }
}

guard FileManager.default.isReadableFile(atPath: patcher) else {
    FileHandle.standardError.write("usage: playwright-watch <path of playwright-background-pages.py>\n".data(using: .utf8)!)
    exit(2)
}
let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
guard let stream = FSEventStreamCreate(nil, callback, nil, watched.filter { FileManager.default.fileExists(atPath: $0) } as CFArray,
                                       FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags) else { exit(1) }
FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
FSEventStreamStart(stream)
dispatchMain()

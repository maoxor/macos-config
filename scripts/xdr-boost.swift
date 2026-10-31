// XDR boost: lets everyday content use the built-in XDR display's 1000 nits, normally kept for HDR (docs/macos.md).
// A click-through window multiplies the screen by a value above SDR white, through Apple's public EDR pipeline: macOS
// raises the backlight as for HDR video and stays in charge of it. No gamma table, no private API, no network, nothing
// stored: when the process ends, however it ends, the window is gone and the screen is back to normal.
// The gain stops at 1000 nits, what Apple rates for sustained full-screen use (600 nits SDR x 1.67, whatever the
// brightness slider says, and never above the headroom macOS grants). It fades out and quits on SIGTERM or if macOS
// reports a serious thermal state.
//   xdr-boost [gain]   run until killed; SIGUSR1 / SIGUSR2 one step up / down (brightness keys, brightness-boost.lua)
import AppKit
import MetalKit

signal(SIGUSR1, SIG_IGN)  // first: a key held down reaches a process that is still starting
signal(SIGUSR2, SIG_IGN)
let maxGain: CGFloat = 1.67
let requested = CommandLine.arguments.dropFirst().first.flatMap { Double($0) }.map { CGFloat($0) } ?? maxGain
let steps: CGFloat = 4
var target = max(1, min(requested, maxGain))
let fadeFramesPerSecond = 30
let idleFramesPerSecond = 2  // not 0: a static frame loses its EDR status. Measured: 1600 nits held, 0.1 % CPU

func builtInScreen() -> NSScreen? {
    NSScreen.screens.first { screen in
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return id.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
    }
}

// The level bar, in Apple's glass since Hammerspoon cannot draw it: macOS's own bar stops at 100 %.
@MainActor final class LevelBar {
    private static let size = CGSize(width: 232, height: 46)
    private let panel: NSPanel
    private let fill = NSView()
    private let trackWidth: CGFloat = 164
    private var hiding: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver + 1  // above the boost window
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let content = NSView(frame: NSRect(origin: .zero, size: Self.size))
        let icon = NSImageView(frame: NSRect(x: 16, y: 12, width: 22, height: 22))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        icon.contentTintColor = .labelColor
        let track = NSView(frame: NSRect(x: 50, y: 20, width: trackWidth, height: 6))
        track.wantsLayer = true
        track.layer?.cornerRadius = 3
        track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
        fill.frame = NSRect(x: 0, y: 0, width: 0, height: 6)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 3
        fill.layer?.backgroundColor = NSColor.labelColor.cgColor
        track.addSubview(fill)
        content.addSubview(icon)
        content.addSubview(track)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = Self.size.height / 2
            glass.contentView = content
            panel.contentView = glass
        } else {
            let glass = NSVisualEffectView(frame: content.frame)
            glass.material = .hudWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = Self.size.height / 2
            glass.layer?.masksToBounds = true
            glass.addSubview(content)
            panel.contentView = glass
        }
    }

    func show(_ share: CGFloat, on screen: NSScreen?) {
        if let frame = screen?.frame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width - 14, y: frame.maxY - Self.size.height - 14))
        }
        hiding?.cancel()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
            fill.animator().frame.size.width = trackWidth * share
        }
        let hide = DispatchWorkItem { [weak self] in self?.hide {} }
        hiding = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: hide)
    }

    func hide(then done: @escaping @MainActor () -> Void) {
        hiding?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { done() } })
    }
}

final class BoostView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private var gain: CGFloat = 1
    private var leaving = false
    private var frames = 0
    private let bar = LevelBar()

    init(frame: NSRect, device: MTLDevice, queue: MTLCommandQueue) {
        self.queue = queue
        super.init(frame: frame, device: device)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.compositingFilter = "multiply"
        (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        preferredFramesPerSecond = fadeFramesPerSecond
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func leave() {
        leaving = true
        wakeUp()
        bar.show(0, on: window?.screen)
    }

    func move(by delta: CGFloat) {
        target = max(1, min(target + delta, maxGain))
        wakeUp()
        bar.show((target - 1) / (maxGain - 1), on: window?.screen)
    }

    private func wakeUp() {
        preferredFramesPerSecond = fadeFramesPerSecond
    }

    func draw(in view: MTKView) {
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if hot, !leaving { leave() }
        // Shown only once its white frames are ready: the window multiplies, so an empty one would black out the Mac.
        frames += 1
        if frames == 3 {
            window?.alphaValue = 1
            bar.show((target - 1) / (maxGain - 1), on: window?.screen)
        }
        // Never ahead of the headroom macOS has opened so far: above it, the screen clips to white.
        let live = window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        let goal = leaving || frames < 3 ? 1 : min(target, max(1, live * 1.1))
        gain += (goal - gain) * 0.18
        if abs(goal - gain) < 0.005 {
            gain = goal
            if leaving {
                isPaused = true
                bar.hide { exit(0) }
                return
            }
            preferredFramesPerSecond = idleFramesPerSecond
        } else {
            preferredFramesPerSecond = fadeFramesPerSecond
        }
        clearColor = MTLClearColor(red: Double(gain), green: Double(gain), blue: Double(gain), alpha: 1)
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = builtInScreen(), screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.01,
      let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    FileHandle.standardError.write(Data("no built-in EDR display\n".utf8))
    exit(1)
}
let view = BoostView(frame: NSRect(origin: .zero, size: screen.frame.size), device: device, queue: queue)
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.setFrame(screen.frame, display: false)
window.alphaValue = 0
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = true
window.sharingType = .none
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
window.contentView = view
window.orderFrontRegardless()
@MainActor func follow() {
    guard let screen = builtInScreen() else {  // lid closed: back as soon as it opens
        window.orderOut(nil)
        return
    }
    window.setFrame(screen.frame, display: true)
    window.orderFrontRegardless()
}
let screenChange = NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in MainActor.assumeIsolated { follow() } }
let wake = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in MainActor.assumeIsolated { follow() } }
var stepSources: [any DispatchSourceSignal] = []
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { MainActor.assumeIsolated { view.leave() } }
termination.resume()
for (number, delta) in [(SIGUSR1, (maxGain - 1) / steps), (SIGUSR2, -(maxGain - 1) / steps)] {
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { view.move(by: delta) } }
    source.resume()
    stepSources.append(source)
}
app.run()

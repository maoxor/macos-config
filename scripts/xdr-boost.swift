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

final class BoostView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private var gain: CGFloat = 1
    private var leaving = false

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
    }

    func move(by delta: CGFloat) {
        target = max(1, min(target + delta, maxGain))
        wakeUp()
    }

    private func wakeUp() {
        preferredFramesPerSecond = fadeFramesPerSecond
    }

    func draw(in view: MTKView) {
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { leave() }
        // Never ahead of the headroom macOS has opened so far: above it, the screen clips to white.
        let live = window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        let goal = leaving ? 1 : min(target, max(1, live * 1.1))
        gain += (goal - gain) * 0.18
        if abs(goal - gain) < 0.005 {
            gain = goal
            if leaving { exit(0) }
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

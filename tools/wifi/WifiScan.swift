// WifiScan.app: lists Wi-Fi networks for the SketchyBar Wi-Fi menu. macOS (14+) hides network names from anything
// without Location Services, so this is a tiny app bundle the user allows once; run with `open -g -W WifiScan.app`.
// Writes ~/.cache/wifi-menu/scan.json: {"auth": "...", "current": "...", "networks": [{"ssid","rssi","secure"}]}
import AppKit; import CoreLocation; import CoreWLAN
final class D: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
  let lm = CLLocationManager()
  func applicationDidFinishLaunching(_ n: Notification) {
    lm.delegate = self
    if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization()
      DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.scan() } } else { scan() }
  }
  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { if m.authorizationStatus != .notDetermined { scan() } }
  var done = false
  func scan() {
    if done { return }; done = true
    let a: String = { switch lm.authorizationStatus { case .authorizedAlways, .authorized: return "ok"
      case .denied, .restricted: return "denied"; default: return "pending" } }()
    let i = CWWiFiClient.shared().interface()
    var nets: [[String: Any]] = []; var seen = Set<String>()
    if let s = try? i?.scanForNetworks(withSSID: nil) {
      for n in s.sorted(by: { $0.rssiValue > $1.rssiValue }) {
        guard let id = n.ssid, !id.isEmpty, seen.insert(id).inserted else { continue }
        nets.append(["ssid": id, "rssi": n.rssiValue, "secure": !n.supportsSecurity(.none)])
      }
    }
    let out: [String: Any] = ["auth": a, "power": i?.powerOn() ?? false, "current": i?.ssid() ?? "", "networks": nets]
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/wifi-menu")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]).write(to: dir.appendingPathComponent("scan.json"))
    NSApp.terminate(nil)
  }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory); let d = D(); app.delegate = d; app.run()

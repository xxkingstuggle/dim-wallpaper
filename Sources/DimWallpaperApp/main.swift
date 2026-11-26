import AppKit
import ServiceManagement
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

let launchOptions = LaunchOptions.parse(
    arguments: CommandLine.arguments,
    environment: ProcessInfo.processInfo.environment
)

if launchOptions.printStatus || launchOptions.printStatusJSON {
    let store = PreferencesStore(suiteName: launchOptions.defaultsSuiteName)
    let snapshot = launchOptions.applyingOverrides(to: store.load())
    let displays = DimWallpaperController.captureOnlineDisplays()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.0"
    let report = DiagnosticReport(
        version: version,
        suiteName: store.suiteName,
        snapshot: snapshot,
        displays: displays,
        loginItemStatus: SMAppService.mainApp.status.rawValue
    )
    if launchOptions.printStatusJSON {
        do {
            print(try report.jsonString())
        } catch {
            FileHandle.standardError.write(Data("Failed to encode status JSON: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    } else {
        print(report.legacyLine())
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(launchOptions: launchOptions)
app.delegate = delegate
app.run()

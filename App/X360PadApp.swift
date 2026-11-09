// A menu-bar app (no Dock icon): the controller icon opens the settings window.
import ServiceManagement
import SwiftUI
import X360PadCore

@main
struct X360PadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: appDelegate.manager, driver: appDelegate.driver)
        } label: {
            Image(systemName: "gamecontroller")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = PadManager()
    let driver = DriverInstaller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["X360PAD_INSTALL_DRIVER"] != nil { driver.install() }
        if ProcessInfo.processInfo.environment["X360PAD_REMOVE_DRIVER"] != nil { driver.uninstall() }
        driver.refresh { _ in }
        manager.start()
    }

}

/// Open at login, through the system's login items (System Settings > General > Login Items).
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("open at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

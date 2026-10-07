import ServiceManagement
import SwiftUI

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Shelf", systemImage: "tray.full") {
            Button("클립보드에서 추가") { delegate.shelf.store.addFromPasteboard() }
            Toggle("로그인 시 실행", isOn: launchAtLogin)
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }
    }
}

private let launchAtLogin = Binding(
    get: { SMAppService.mainApp.status == .enabled },
    set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
)

final class AppDelegate: NSObject, NSApplicationDelegate {
    let shelf = ShelfPanel(store: Store())

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        shelf.start()
    }
}

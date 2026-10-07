import ServiceManagement
import SwiftUI

@main
struct ClipShelfApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("ClipShelf", systemImage: "tray.full") {
            Button(L("클립보드에서 추가", "Add from Clipboard")) { delegate.shelf.store.addFromPasteboard() }
            Toggle(L("로그인 시 실행", "Launch at Login"), isOn: launchAtLogin)
            Divider()
            Button(L("종료", "Quit")) { NSApp.terminate(nil) }
        }
    }
}

/// 시스템 언어가 한국어면 ko, 아니면 en. 문자열 7개뿐이라 xcstrings 대신 이걸로.
func L(_ ko: String, _ en: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ko") == true ? ko : en
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

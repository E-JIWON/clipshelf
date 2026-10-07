import SwiftUI

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Shelf", systemImage: "tray.full") {
            Button("클립보드에서 추가") { delegate.shelf.store.addFromPasteboard() }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let shelf = ShelfPanel(store: Store())

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        shelf.start()
    }
}

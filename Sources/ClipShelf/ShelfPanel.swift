import AppKit
import Combine
import Quartz
import SwiftUI

/// 앱을 활성화하지 않고도 키 입력(⌘V)을 받는 패널.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 마우스가 패널 위에 들어오고 나가는 것만 알려주는 호스팅 뷰. 전역 마우스 감시 없이 이것만으로 숨김/펼침을 정한다.
private final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onMouseExited?() }
}

/// 화면 가장자리에 붙어 있는 선반 패널. 숨김/펼침, 가장자리 스냅, 드래그 감지, 미리보기를 담당한다.
final class ShelfPanel {
    private enum Layout {
        static let peek: CGFloat = 10 // 숨었을 때 삐져나오는 탭 폭. 여기에 마우스를 대면 펼쳐진다
        static let hideDelay: TimeInterval = 0.5
    }

    let store: Store
    private let panel: NSPanel
    private let preview = NSPopover()

    private var home = NSRect.zero // 펼쳐진 자리(가장자리에 스냅된 프레임)
    private var isShown = true
    private var isMovingProgrammatically = false
    private var isExternalDragActive = false
    private var lastDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var hideWork: DispatchWorkItem?
    private var snapWork: DispatchWorkItem?
    private var pinObserver: AnyCancellable?

    init(store: Store) {
        self.store = store
        panel = KeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        preview.behavior = .transient
    }

    func start() {
        configurePanel()
        home = UserDefaults.standard.string(forKey: "frame").map(NSRectFromString) ?? defaultFrame()
        move(to: home, animate: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panelDidMove()
        }
        // 드래그 페이스트보드의 changeCount가 바뀌면 어딘가에서 드래그가 시작된 것
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.detectExternalDrag()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        // 외부 드래그가 끝나면(버튼 뗌) 마우스가 패널 밖일 때 숨김
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.isExternalDragActive = false
            self?.scheduleHideIfMouseOutside()
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closePreviewIfClickedOutside()
        }
        pinObserver = store.$pinned.sink { [weak self] pinned in
            self?.panel.isMovableByWindowBackground = !pinned
            if pinned { self?.show() } else { self?.scheduleHideIfMouseOutside() }
        }
        installSnapshotHook()
    }

    // MARK: - Preview

    func showPreview(for url: URL, from view: NSView) {
        if preview.isShown { preview.close(); return }
        if Store.text(of: url) != nil {
            preview.contentViewController = NSHostingController(rootView: TextEditView(url: url, store: store))
        } else {
            guard let quickLook = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 360, height: 360), style: .normal) else { return }
            quickLook.previewItem = url as NSURL
            quickLook.autostarts = true
            let controller = NSViewController()
            controller.view = quickLook
            preview.contentViewController = controller
        }
        preview.show(relativeTo: view.bounds, of: view, preferredEdge: isOnLeft ? .maxX : .minX)
        preview.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let hosting = TrackingHostingView(rootView: ShelfView(store: store) { [weak self] url, view in
            self?.showPreview(for: url, from: view)
        })
        hosting.onMouseEntered = { [weak self] in self?.show() }
        hosting.onMouseExited = { [weak self] in self?.scheduleHide() }
        panel.contentView = hosting
    }

    private func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        return NSRect(x: visible.minX, y: visible.midY - ShelfView.size.height / 2,
                      width: ShelfView.size.width, height: ShelfView.size.height)
    }

    // MARK: - Geometry

    private var screen: NSScreen {
        NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main!
    }

    private var isOnLeft: Bool { home.midX < screen.frame.midX }

    private func move(to frame: NSRect, animate: Bool) {
        isMovingProgrammatically = true
        panel.setFrame(frame, display: true, animate: animate)
        isMovingProgrammatically = false
    }

    private func panelDidMove() {
        guard !isMovingProgrammatically else { return }
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapToEdge() }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// 사용자가 놓은 자리에서 가까운 좌/우 가장자리로 붙이고 기억한다.
    private func snapToEdge() {
        guard isShown else { return }
        guard NSEvent.pressedMouseButtons == 0 else { panelDidMove(); return }
        let current = screen
        let visible = current.visibleFrame
        var frame = panel.frame
        frame.origin.x = frame.midX < current.frame.midX ? visible.minX : visible.maxX - frame.width
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        home = frame
        move(to: frame, animate: true)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "frame")
    }

    // MARK: - Show / hide

    private func detectExternalDrag() {
        let count = NSPasteboard(name: .drag).changeCount
        guard count != lastDragChangeCount else { return }
        lastDragChangeCount = count
        isExternalDragActive = true
        show()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard NSApp.keyWindow === panel, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers == "v" else { return event }
        store.addFromPasteboard()
        return nil
    }

    private func scheduleHide() {
        guard isShown, !store.pinned, !isExternalDragActive, !preview.isShown, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.hideDelay, execute: work)
    }

    private func scheduleHideIfMouseOutside() {
        if !panel.frame.contains(NSEvent.mouseLocation) { scheduleHide() }
    }

    private func closePreviewIfClickedOutside() {
        guard preview.isShown else { return }
        let mouse = NSEvent.mouseLocation
        let inPreview = preview.contentViewController?.view.window?.frame.contains(mouse) ?? false
        if !inPreview, !panel.frame.contains(mouse) {
            preview.close()
            scheduleHideIfMouseOutside()
        }
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func show() {
        cancelHide()
        guard !isShown else { return }
        isShown = true
        move(to: home, animate: true)
    }

    private func hide() {
        hideWork = nil
        guard isShown, !store.pinned, !isExternalDragActive, !preview.isShown else { return }
        guard NSEvent.pressedMouseButtons == 0 else { scheduleHide(); return } // 패널을 끌어 옮기는 중
        isShown = false
        var frame = home
        frame.origin.x = isOnLeft ? screen.frame.minX + Layout.peek - frame.width : screen.frame.maxX - Layout.peek
        move(to: frame, animate: true)
    }

    // MARK: - Debug

    /// `kill -USR1 <pid>` 하면 패널을 PNG로 저장한다. UI 점검·README 스크린샷용.
    private func installSnapshotHook() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            guard let view = self?.panel.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = Store.defaultDirectory.deletingLastPathComponent().appendingPathComponent("ClipShelf-snapshot.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        source.resume()
        snapshotSource = source
    }

    private var snapshotSource: DispatchSourceSignal?
}

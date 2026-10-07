import AppKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

// 선반 = 폴더 하나. 폴더 안의 파일이 곧 아이템. (.txt는 텍스트, 나머지는 이미지/파일)
final class Store: ObservableObject {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    @Published var items: [URL] = []

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        items = urls.sorted { mtime($0) > mtime($1) }
    }

    private func mtime(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func fresh(_ ext: String) -> URL {
        Self.dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))").appendingPathExtension(ext)
    }

    func add(text: String) {
        try? text.write(to: fresh("txt"), atomically: true, encoding: .utf8)
        reload()
    }

    func add(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: fresh("png"))
        reload()
    }

    func add(file: URL) {
        try? FileManager.default.copyItem(at: file, to: fresh(file.pathExtension.isEmpty ? "bin" : file.pathExtension))
        reload()
    }

    func remove(_ u: URL) {
        try? FileManager.default.removeItem(at: u)
        reload()
    }

    func addFromPasteboard(_ pb: NSPasteboard = .general) {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach(add(file:)); return
        }
        if let img = NSImage(pasteboard: pb) { add(image: img); return }
        if let s = pb.string(forType: .string), !s.isEmpty { add(text: s) }
    }

    func add(providers: [NSItemProvider]) -> Bool {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { self.add(file: url) }
                }
            } else if p.canLoadObject(ofClass: NSImage.self) {
                p.loadObject(ofClass: NSImage.self) { img, _ in
                    if let img = img as? NSImage { DispatchQueue.main.async { self.add(image: img) } }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                p.loadObject(ofClass: NSString.self) { s, _ in
                    if let s = s as? String { DispatchQueue.main.async { self.add(text: s) } }
                }
            }
        }
        return !providers.isEmpty
    }

    static func text(of u: URL) -> String? {
        u.pathExtension == "txt" ? try? String(contentsOf: u, encoding: .utf8) : nil
    }

    // ponytail: 이미지는 파일 URL로만 복사. 이미지 데이터 자체가 필요한 앱은 드래그로 꺼내면 됨.
    func copy(_ u: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let s = Self.text(of: u) { pb.setString(s, forType: .string) } else { pb.writeObjects([u as NSURL]) }
    }
}

// 카드 위에 얹는 투명 NSView. 클릭 → 미리보기, 끌기 → AppKit 드래그 세션.
// (SwiftUI onDrag는 Finder/다른 앱이 받는 public.file-url을 안 실어줘서 꺼내기가 안 됨)
final class DragHandle: NSView, NSDraggingSource {
    var url: URL!
    var onClick: ((NSView) -> Void)?
    private var down = NSPoint.zero

    override func mouseDown(with e: NSEvent) { down = e.locationInWindow }
    override func mouseUp(with _: NSEvent) { onClick?(self) }
    override func mouseDragged(with e: NSEvent) {
        guard hypot(e.locationInWindow.x - down.x, e.locationInWindow.y - down.y) > 4 else { return }
        let item = NSPasteboardItem()
        if let s = Store.text(of: url) {
            item.setString(s, forType: .string)
        } else {
            item.setString(url.absoluteString, forType: .fileURL)
            if let t = UTType(filenameExtension: url.pathExtension), t.conforms(to: .image), let data = try? Data(contentsOf: url) {
                item.setData(data, forType: NSPasteboard.PasteboardType(t.identifier))
            }
        }
        let d = NSDraggingItem(pasteboardWriter: item)
        d.setDraggingFrame(bounds, contents: NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [d], event: e, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation { .copy }
}

struct Draggable: NSViewRepresentable {
    let url: URL
    let onClick: (NSView) -> Void
    func makeNSView(context _: Context) -> DragHandle { DragHandle() }
    func updateNSView(_ v: DragHandle, context _: Context) { v.url = url; v.onClick = onClick }
}

struct Card: View {
    let url: URL
    @ObservedObject var store: Store
    var body: some View {
        Group {
            if let s = Store.text(of: url) {
                Text(s).font(.caption).lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else if let img = NSImage(contentsOf: url) { // ponytail: 매 렌더마다 디스크 읽음, 느려지면 캐시
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Label(url.lastPathComponent, systemImage: "doc").font(.caption).lineLimit(2).padding(6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        .overlay(Draggable(url: url) { delegate.preview(url, from: $0) })
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Button { store.copy(url) } label: { Image(systemName: "doc.on.doc.fill") }
                Button { store.remove(url) } label: { Image(systemName: "xmark") }
            }
            .buttonStyle(.plain).font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(4)
        }
        .help("클릭: 미리보기 · 드래그: 꺼내기")
    }
}

struct ShelfView: View {
    @ObservedObject var store: Store
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("선반").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { store.addFromPasteboard() } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.plain).help("클립보드에서 추가")
            }
            if store.items.isEmpty {
                Spacer()
                Text("여기로\n끌어다 놓기").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.items, id: \.self) { Card(url: $0, store: store) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 160, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? Color.accentColor : .clear, lineWidth: 2))
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $targeted) { store.add(providers: $0) }
    }
}

// 앱을 활성화하지 않고도 키 입력(Cmd+V)을 받을 수 있는 패널
final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: NSPanel!
    var status: NSStatusItem!
    var pinItem: NSMenuItem!
    let previewPopover: NSPopover = { let p = NSPopover(); p.behavior = .transient; return p }()

    static let peek: CGFloat = 8 // 숨었을 때 삐져나오는 폭
    var home = NSRect.zero // 펼쳐졌을 때 자리 (가장자리에 스냅된 상태)
    var shown = true
    var pinned = false
    var moving = false // 코드로 setFrame 중 (didMove 무시)
    var dragging = false // 다른 앱에서 뭔가 드래그 중
    var lastDrag = NSPasteboard(name: .drag).changeCount
    var hideTicks = 0
    var snapWork: DispatchWorkItem?

    var screen: NSScreen { NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main! }
    var onLeft: Bool { home.midX < screen.frame.midX }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory) // Dock 아이콘 없음

        panel = KeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(store: store))
        let vis = NSScreen.main?.visibleFrame ?? .zero
        home = UserDefaults.standard.string(forKey: "frame").map(NSRectFromString)
            ?? NSRect(x: vis.minX, y: vis.midY - 210, width: 160, height: 420)
        move(to: home, animate: false)
        panel.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Shelf")
        let menu = NSMenu()
        pinItem = NSMenuItem(title: "항상 보이기", action: #selector(togglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        let pasteItem = NSMenuItem(title: "클립보드에서 추가", action: #selector(paste), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu

        // 패널 옮기면 가까운 좌/우 가장자리에 붙이고 위치 기억
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, !self.moving else { return }
            self.scheduleSnap()
        }
        // Yoink 방식: 드래그 페이스트보드가 바뀌면 어딘가에서 드래그가 시작된 것
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.detectDrag() }
        // 선반 클릭해서 포커스 준 뒤 Cmd+V → 클립보드 내용 추가
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "v" else { return e }
            self?.store.addFromPasteboard()
            return nil
        }
        // ponytail: 10Hz 폴링으로 마우스 위치 감시
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    @objc func togglePin() { pinned.toggle(); pinItem.state = pinned ? .on : .off; if pinned { show() } }
    @objc func paste() { store.addFromPasteboard() }

    func preview(_ url: URL, from view: NSView) {
        if previewPopover.isShown { previewPopover.close(); return }
        guard let ql = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 360, height: 360), style: .normal) else { return }
        ql.previewItem = url as NSURL
        ql.autostarts = true
        let vc = NSViewController()
        vc.view = ql
        previewPopover.contentViewController = vc
        previewPopover.show(relativeTo: view.bounds, of: view, preferredEdge: onLeft ? .maxX : .minX)
    }

    func move(to f: NSRect, animate: Bool) {
        moving = true
        panel.setFrame(f, display: true, animate: animate)
        moving = false
    }

    func scheduleSnap() {
        snapWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.snap() }
        snapWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func snap() {
        guard shown else { return }
        guard NSEvent.pressedMouseButtons == 0 else { scheduleSnap(); return }
        let s = screen, vis = s.visibleFrame
        var f = panel.frame
        f.origin.x = f.midX < s.frame.midX ? vis.minX : vis.maxX - f.width
        f.origin.y = min(max(f.minY, vis.minY), vis.maxY - f.height)
        home = f
        move(to: f, animate: true)
        UserDefaults.standard.set(NSStringFromRect(f), forKey: "frame")
    }

    func detectDrag() {
        let c = NSPasteboard(name: .drag).changeCount
        if c != lastDrag { lastDrag = c; dragging = true; show() }
    }

    func tick() {
        let m = NSEvent.mouseLocation
        if dragging, NSEvent.pressedMouseButtons == 0 { dragging = false }
        if previewPopover.isShown {
            let inPopover = previewPopover.contentViewController?.view.window?.frame.contains(m) ?? false
            if NSEvent.pressedMouseButtons != 0, !inPopover, !panel.frame.contains(m) { previewPopover.close() }
            return
        }
        if !shown {
            // 삐져나온 탭 근처(위아래 40px 여유)에 마우스가 오면 펼침
            if dragging || panel.frame.insetBy(dx: -4, dy: -40).contains(m) { show() }
        } else if dragging || pinned || panel.frame.insetBy(dx: -24, dy: -24).contains(m) {
            hideTicks = 0
        } else {
            hideTicks += 1
            if hideTicks > 5 { hide() }
        }
    }

    func show() {
        hideTicks = 0
        guard !shown else { return }
        shown = true
        move(to: home, animate: true)
    }

    func hide() {
        guard shown else { return }
        shown = false
        var f = home
        f.origin.x = onLeft ? screen.frame.minX + Self.peek - f.width : screen.frame.maxX - Self.peek
        move(to: f, animate: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

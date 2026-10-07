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
    @Published var toast: String?
    @Published var pinned = false

    init() { reload() }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        items = urls.sorted { $0.lastPathComponent > $1.lastPathComponent } // 파일명 = 생성 시각. 수정해도 순서 안 바뀜
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

    func update(_ u: URL, text: String) {
        try? text.write(to: u, atomically: true, encoding: .utf8)
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
        toast = "복사됨"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.toast = nil }
    }
}

// 카드 위에 얹는 투명 NSView. 클릭 → 미리보기, 끌기 → AppKit 드래그 세션, 호버 감지.
// (SwiftUI onDrag는 Finder/다른 앱이 받는 public.file-url을 안 실어줘서 꺼내기가 안 됨)
final class DragHandle: NSView, NSDraggingSource {
    var url: URL!
    var onClick: ((NSView) -> Void)?
    var onHover: ((Bool) -> Void)?
    private var down = NSPoint.zero

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with _: NSEvent) { onHover?(true) }
    override func mouseExited(with _: NSEvent) { onHover?(false) }
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
    let onHover: (Bool) -> Void
    func makeNSView(context _: Context) -> DragHandle { DragHandle() }
    func updateNSView(_ v: DragHandle, context _: Context) { v.url = url; v.onClick = onClick; v.onHover = onHover }
}

struct Card: View {
    let url: URL
    @ObservedObject var store: Store
    @State private var hover = false

    func dot(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain).padding(5)
    }

    var body: some View {
        Group {
            if let s = Store.text(of: url) {
                Text(s).font(.system(size: 11)).lineLimit(5).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(.primary.opacity(0.06))
            } else if let img = NSImage(contentsOf: url) { // ponytail: 매 렌더마다 디스크 읽음, 느려지면 캐시
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Label(url.lastPathComponent, systemImage: "doc.fill").font(.system(size: 11)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(.primary.opacity(0.06))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .overlay(Draggable(url: url, onClick: { delegate.preview(url, from: $0) }, onHover: { hover = $0 }))
        .overlay(alignment: .bottomLeading) { if hover { dot("doc.on.doc.fill") { store.copy(url) } } }
        .overlay(alignment: .bottomTrailing) { if hover { dot("xmark") { store.remove(url) } } }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help("클릭: 미리보기/편집 · 드래그: 꺼내기")
    }
}

struct TextEditView: View {
    let url: URL
    @ObservedObject var store: Store
    @State private var text: String

    init(url: URL, store: Store) {
        self.url = url
        self.store = store
        _text = State(initialValue: Store.text(of: url) ?? "")
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12)).lineSpacing(2)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(width: 300, height: 220)
            .onChange(of: text) { _, new in store.update(url, text: new) }
    }
}

struct ShelfView: View {
    @ObservedObject var store: Store
    @State private var targeted = false
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 22, weight: .light))
                    Text("끌어다 놓기\n또는 ⌘V").font(.system(size: 11)).multilineTextAlignment(.center)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.items, id: \.self) { Card(url: $0, store: store) }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 160, height: 420)
        .background(.thinMaterial, in: shape)
        .overlay(shape.fill(Color.accentColor.opacity(targeted ? 0.1 : 0)))
        .overlay(shape.strokeBorder(targeted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: 1))
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { store.pinned.toggle() } label: {
                Image(systemName: store.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.pinned ? Color.white : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(store.pinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.08)), in: Circle())
            }
            .buttonStyle(.plain).padding(7)
            .help(store.pinned ? "고정 해제" : "고정: 위치 잠금 + 항상 열림")
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $targeted) { store.add(providers: $0) }
    }
}

// 앱을 활성화하지 않고도 키 입력(Cmd+V)을 받을 수 있는 패널
final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: NSPanel!
    var status: NSStatusItem!
    let previewPopover: NSPopover = { let p = NSPopover(); p.behavior = .transient; return p }()

    static let peek: CGFloat = 8 // 숨었을 때 삐져나오는 폭
    var home = NSRect.zero // 펼쳐졌을 때 자리 (가장자리에 스냅된 상태)
    var shown = true
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
            guard NSApp.keyWindow === self?.panel, e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "v" else { return e }
            self?.store.addFromPasteboard()
            return nil
        }
        // ponytail: 10Hz 폴링으로 마우스 위치 감시
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    @objc func paste() { store.addFromPasteboard() }

    func preview(_ url: URL, from view: NSView) {
        if previewPopover.isShown { previewPopover.close(); return }
        if Store.text(of: url) != nil { // 텍스트는 미리보기 대신 바로 편집
            previewPopover.contentViewController = NSHostingController(rootView: TextEditView(url: url, store: store))
            previewPopover.show(relativeTo: view.bounds, of: view, preferredEdge: onLeft ? .maxX : .minX)
            previewPopover.contentViewController?.view.window?.makeKey()
            return
        }
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
        panel.isMovableByWindowBackground = !store.pinned // 고정 = 위치 잠금
        if store.pinned { show() }
        if dragging, NSEvent.pressedMouseButtons == 0 { dragging = false }
        if previewPopover.isShown {
            let inPopover = previewPopover.contentViewController?.view.window?.frame.contains(m) ?? false
            if NSEvent.pressedMouseButtons != 0, !inPopover, !panel.frame.contains(m) { previewPopover.close() }
            return
        }
        if !shown {
            // 삐져나온 탭 근처(위아래 40px 여유)에 마우스가 오면 펼침
            if dragging || panel.frame.insetBy(dx: -4, dy: -40).contains(m) { show() }
        } else if dragging || store.pinned || panel.frame.insetBy(dx: -24, dy: -24).contains(m) {
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

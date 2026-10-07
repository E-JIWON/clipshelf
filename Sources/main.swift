import AppKit
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

struct Card: View {
    let url: URL
    @ObservedObject var store: Store
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            .contentShape(Rectangle())
            .onTapGesture { store.copy(url) }
            .onDrag {
                if let s = Store.text(of: url) { return NSItemProvider(object: s as NSString) }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            if hover {
                Button { store.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).padding(3)
            }
        }
        .onHover { hover = $0 }
        .help("클릭: 복사 · 드래그: 꺼내기")
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var panel: NSPanel!
    var status: NSStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory) // Dock 아이콘 없음

        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(store: store))
        let s = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: s.minX + 8, y: s.midY - 210, width: 160, height: 420), display: true)
        panel.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Shelf")
        let menu = NSMenu()
        for (title, sel) in [("선반 보이기/숨기기", #selector(toggle)), ("클립보드에서 추가", #selector(paste))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
    }

    @objc func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc func paste() { store.addFromPasteboard() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

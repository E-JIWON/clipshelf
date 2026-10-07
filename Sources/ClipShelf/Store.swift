import AppKit
import UniformTypeIdentifiers

/// 선반 = 폴더 하나. 폴더 안의 파일이 곧 아이템. `.txt`는 텍스트, 나머지는 이미지/파일.
final class Store: ObservableObject {
    static let defaultDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClipShelf", isDirectory: true)

    let directory: URL
    @Published private(set) var items: [URL] = []
    @Published var toast: String?
    @Published var pinned = false

    private var watcher: DispatchSourceFileSystemObject?

    init(directory: URL = Store.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        watchDirectory()
    }

    deinit { watcher?.cancel() }

    static func text(of url: URL) -> String? {
        url.pathExtension == "txt" ? try? String(contentsOf: url, encoding: .utf8) : nil
    }

    // MARK: - Mutations

    func add(text: String) {
        try? text.write(to: newURL("txt"), atomically: true, encoding: .utf8)
        reload()
    }

    func add(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: newURL("png"))
        reload()
    }

    func add(file: URL) {
        try? FileManager.default.copyItem(at: file, to: newURL(file.pathExtension.isEmpty ? "bin" : file.pathExtension))
        reload()
    }

    func addFromPasteboard(_ pasteboard: NSPasteboard = .general) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            urls.forEach(add(file:))
        } else if let image = NSImage(pasteboard: pasteboard) {
            add(image: image)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            add(text: text)
        }
    }

    @discardableResult
    func add(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { self.add(file: url) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    DispatchQueue.main.async { self.add(image: image) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let text = text as? String else { return }
                    DispatchQueue.main.async { self.add(text: text) }
                }
            }
        }
        return !providers.isEmpty
    }

    func update(_ url: URL, text: String) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    // ponytail: 이미지는 파일 URL로만 복사. 이미지 데이터가 필요한 앱은 드래그로 꺼내면 됨.
    func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if let text = Self.text(of: url) {
            pasteboard.setString(text, forType: .string)
        } else {
            pasteboard.writeObjects([url as NSURL])
        }
        showToast(L("복사됨", "Copied"))
    }

    // MARK: - Private

    private func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        items = urls.sorted { $0.lastPathComponent > $1.lastPathComponent } // 파일명이 생성 시각이라 수정해도 순서가 안 바뀜
    }

    /// 폴더가 바깥에서 바뀌어도(다른 인스턴스, 스크립트) 목록을 맞춘다.
    private func watchDirectory() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func newURL(_ ext: String) -> URL {
        directory.appendingPathComponent(String(Int(Date().timeIntervalSince1970 * 1000))).appendingPathExtension(ext)
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.toast = nil }
    }
}

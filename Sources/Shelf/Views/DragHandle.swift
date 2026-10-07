import SwiftUI
import UniformTypeIdentifiers

/// 카드 위에 얹는 투명 NSView. 클릭·호버 감지, 끌기는 AppKit 드래그 세션으로 시작한다.
/// SwiftUI `onDrag`는 Finder 등이 받는 `public.file-url`을 싣지 않아 꺼내기가 안 된다.
final class DragHandle: NSView, NSDraggingSource {
    var url: URL!
    var onClick: ((NSView) -> Void)?
    var onHover: ((Bool) -> Void)?
    private var mouseDownPoint = NSPoint.zero

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with _: NSEvent) { onHover?(true) }
    override func mouseExited(with _: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
    override func mouseUp(with _: NSEvent) { onClick?(self) }

    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 4 else { return }
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem())
        item.setDraggingFrame(bounds, contents: NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation { .copy }

    private func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if let text = Store.text(of: url) {
            item.setString(text, forType: .string)
            return item
        }
        item.setString(url.absoluteString, forType: .fileURL)
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        return item
    }
}

struct Draggable: NSViewRepresentable {
    let url: URL
    let onClick: (NSView) -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> DragHandle { DragHandle() }

    func updateNSView(_ view: DragHandle, context _: Context) {
        view.url = url
        view.onClick = onClick
        view.onHover = onHover
    }
}

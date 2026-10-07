import SwiftUI

struct Card: View {
    let url: URL
    @ObservedObject var store: Store
    let onPreview: (URL, NSView) -> Void
    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            .overlay(Draggable(url: url, onClick: { onPreview(url, $0) }, onHover: { hovering = $0 }))
            .overlay(alignment: .bottomLeading) { if hovering { actionButton("doc.on.doc.fill") { store.copy(url) } } }
            .overlay(alignment: .bottomTrailing) { if hovering { actionButton("xmark") { store.remove(url) } } }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help("클릭: 미리보기/편집 · 드래그: 꺼내기")
    }

    @ViewBuilder
    private var content: some View {
        if let text = Store.text(of: url) {
            Text(text).font(.system(size: 11)).lineLimit(5).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .background(.primary.opacity(0.06))
        } else if let image = NSImage(contentsOf: url) { // ponytail: 매 렌더마다 디스크 읽음, 느려지면 캐시
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Label(url.lastPathComponent, systemImage: "doc.fill").font(.system(size: 11)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .background(.primary.opacity(0.06))
        }
    }

    private func actionButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain).padding(5)
    }
}

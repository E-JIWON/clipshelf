import SwiftUI

struct ShelfView: View {
    static let size = CGSize(width: 160, height: 420)

    @ObservedObject var store: Store
    let onPreview: (URL, NSView) -> Void
    @State private var dropTargeted = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .background(.thinMaterial, in: shape)
            .overlay(shape.fill(Color.accentColor.opacity(dropTargeted ? 0.1 : 0)))
            .overlay(shape.strokeBorder(dropTargeted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1)))
            .overlay(alignment: .bottom) { toast }
            .overlay(alignment: .bottomTrailing) { pinButton }
            .animation(.easeOut(duration: 0.2), value: store.toast)
            .animation(.easeOut(duration: 0.15), value: dropTargeted)
            .onDrop(of: [.fileURL, .image, .text], isTargeted: $dropTargeted) { store.add(providers: $0) }
    }

    @ViewBuilder
    private var content: some View {
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
                    ForEach(store.items, id: \.self) { Card(url: $0, store: store, onPreview: onPreview) }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = store.toast {
            Text(message).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var pinButton: some View {
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
}

import SwiftUI

/// 텍스트 카드 편집. 타이핑하는 대로 파일에 저장된다.
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

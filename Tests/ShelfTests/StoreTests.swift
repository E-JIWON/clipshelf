import AppKit
import XCTest
@testable import Shelf

final class StoreTests: XCTestCase {
    private var dir: URL!
    private var store: Store!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfTests-\(UUID().uuidString)")
        store = Store(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAddTextCreatesTxtItemReadableBack() {
        store.add(text: "hello")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(Store.text(of: store.items[0]), "hello")
    }

    func testNewestItemComesFirstAndEditingKeepsOrder() {
        store.add(text: "first")
        Thread.sleep(forTimeInterval: 0.002)
        store.add(text: "second")
        XCTAssertEqual(Store.text(of: store.items[0]), "second")

        store.update(store.items[1], text: "first-edited")
        XCTAssertEqual(Store.text(of: store.items[1]), "first-edited", "수정해도 순서가 바뀌면 안 됨")
    }

    func testAddImageWritesPNG() {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        store.add(image: image)
        XCTAssertEqual(store.items.first?.pathExtension, "png")
        XCTAssertNotNil(NSImage(contentsOf: store.items[0]))
        XCTAssertNil(Store.text(of: store.items[0]))
    }

    func testAddFileCopiesWithOriginalExtension() throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        store.add(file: src)
        XCTAssertEqual(store.items.first?.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "원본은 남아 있어야 함")
    }

    func testRemoveDeletesFile() {
        store.add(text: "bye")
        let url = store.items[0]
        store.remove(url)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPasteboardRoundTrip() {
        let pb = NSPasteboard(name: NSPasteboard.Name("ShelfTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("from clipboard", forType: .string)
        store.addFromPasteboard(pb)
        XCTAssertEqual(Store.text(of: store.items[0]), "from clipboard")

        pb.clearContents()
        store.copy(store.items[0], to: pb)
        XCTAssertEqual(pb.string(forType: .string), "from clipboard")
        XCTAssertEqual(store.toast, "복사됨")
    }

    func testReopeningStoreSeesExistingFiles() {
        store.add(text: "persisted")
        let reopened = Store(directory: dir)
        XCTAssertEqual(reopened.items.count, 1)
    }
}

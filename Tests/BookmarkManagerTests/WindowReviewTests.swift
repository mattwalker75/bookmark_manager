import XCTest
import AppKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Review 2 (Oct 30 2026), the window layer: the reviewer's cases, asserting the fixed behaviour.
@MainActor
final class WindowReviewTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-win-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; m.importFileForTest(Sample.library()); return m }

    func testTheFocusFollowsTheRows() throws {
        let m = model()
        let work = try XCTUnwrap(m.library.tabs.first { $0.name == "Work" })
        m.selectTab(work.id)
        let tailscale = try XCTUnwrap(work.bookmarks.first { $0.name == "Tailscale admin" })
        let reading = try XCTUnwrap(work.folders.first { $0.name == "Reading" })
        let rows = m.keyboardRows
        m.focusId = tailscale.id
        XCTAssertTrue(m.drop(DragItem.bookmark(tailscale.id).token, to: FolderPath([work.id, reading.id])))
        XCTAssertFalse(m.keyboardRows.contains(tailscale.id))
        XCTAssertNotEqual(m.focusId, tailscale.id, "a row dragged away is nobody's focus")
        XCTAssertEqual(m.focusId, m.keyboardRows[min(rows.firstIndex(of: tailscale.id)!, m.keyboardRows.count - 1)], "the row in its place has it")
        XCTAssertNil(m.focusedBookmark.map { $0.id == tailscale.id ? $0 : nil } ?? nil)
        // a deleted last row hands the focus to the new last row
        let last = try XCTUnwrap(m.currentFolder?.bookmarks.last)
        m.focusId = last.id
        m.deleteBookmark(last.id)
        XCTAssertEqual(m.focusId, m.keyboardRows.last)
        // a stale id acts on nothing
        m.focusId = tailscale.id
        XCTAssertNil(m.focusedBookmark)
        let before = m.selectedPath
        m.activateFocus()
        XCTAssertEqual(m.selectedPath, before)
    }

    func testShowInPlaceLandsTheRowUnderTheArrowKeys() throws {
        let m = model()
        let hit = try XCTUnwrap(m.library.search("tailscale").first)
        m.showInPlace(hit)
        XCTAssertEqual(m.focusId, hit.id)
        XCTAssertEqual(m.highlightId, hit.id)
        m.focusId = nil
        m.reveal(bookmark: hit.id)
        XCTAssertEqual(m.focusId, hit.id)
    }

    func testDeletedDirectoriesLeaveTheOpenBranchesAtOnce() throws {
        let m = model()
        let work = try XCTUnwrap(m.library.tabs.first { $0.name == "Work" })
        let reading = try XCTUnwrap(work.folders.first { $0.name == "Reading" })
        m.setExpanded(reading.id, true)
        for b in reading.bookmarks { m.deleteBookmark(b.id) }
        m.deleteFolder(reading.id)
        XCTAssertFalse(m.settings.expanded.contains(reading.id))
    }

    func testOneVeryLongLineGetsTheRowsItWraps() {
        let screen = NSSize(width: 1728, height: 1084)
        let long = SecretWindows.fittedSize(for: String(repeating: "abcdefghij", count: 150), screen: screen)
        XCTAssertEqual(long.width, 1036, "capped at 60% of the screen's width")
        XCTAssertGreaterThan(long.height, SecretWindows.floor.height + 20, "and tall enough for the wrapped rows")
        let many = SecretWindows.fittedSize(for: Array(repeating: "line", count: 2000).joined(separator: "\n"), screen: screen)
        XCTAssertEqual(many.height, 758); XCTAssertEqual(many.width, SecretWindows.floor.width)
        let plain = SecretWindows.fittedSize(for: String(repeating: "x", count: 60), screen: screen)
        let emoji = SecretWindows.fittedSize(for: String(repeating: "🔑", count: 60), screen: screen)
        XCTAssertGreaterThan(emoji.width, plain.width)
    }

    func testASecretOnlyItemKeepsNoBrowser() throws {
        var lib = Library.fresh()
        let tab = FolderPath(tab: lib.tabs[0].id)
        var b = Bookmark(name: "x", url: "https://x.example", hasSecret: true, secret: "s", browser: "com.google.Chrome")
        try lib.addBookmark(b, in: tab)
        // what the editor does on save with Secret only picked
        b.url = ""; b.hasSecret = true; b.browser = nil
        try lib.updateBookmark(b)
        XCTAssertNil(lib.bookmark(b.id)?.browser)
    }
}

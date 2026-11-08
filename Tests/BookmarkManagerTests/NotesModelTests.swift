import XCTest
import AppKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Notes on a bookmark, the app side (Matt, Nov 8 2026): the window's save and delete through the model, the
/// keyboard, the window sizing, the quit check with nothing open.
@MainActor
final class NotesModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; m.importFileForTest(Sample.library()); return m }

    func testSaveAndDeleteGoThroughTheModelAndReachTheDisk() throws {
        let m = model()
        let pm = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "People Manager" })
        XCTAssertTrue(pm.hasNotes, "the sample has notes on People Manager")
        XCTAssertTrue(m.saveNotes(pm.id, "Where I was: done."))
        let saved = try XCTUnwrap(m.library.bookmark(pm.id))
        XCTAssertEqual(saved.notes, "Where I was: done."); XCTAssertNotNil(saved.notesEditedAt)
        XCTAssertGreaterThan(saved.notesEditedAt!, pm.notesEditedAt!, "the date moved to now")
        XCTAssertEqual(try LibraryStore(folder: home).load().bookmark(pm.id)?.notes, "Where I was: done.")
        // saving the same text again keeps the date
        let stamp = saved.notesEditedAt
        XCTAssertTrue(m.saveNotes(pm.id, "Where I was: done."))
        XCTAssertEqual(m.library.bookmark(pm.id)?.notesEditedAt, stamp)
        // delete: the bookmark stays, the notes are off, so the row has no Notes button any more (Matt)
        m.deleteNotes(pm.id)
        let after = try XCTUnwrap(m.library.bookmark(pm.id))
        XCTAssertFalse(after.hasNotes); XCTAssertEqual(after.notes, ""); XCTAssertNil(after.notesEditedAt)
        XCTAssertEqual(after.name, "People Manager"); XCTAssertNil(m.notice)
        // turned on again from the editor's side: notes with nothing typed are allowed, and get text later
        var again = after; again.hasNotes = true
        m.updateBookmark(again)
        XCTAssertTrue(m.library.bookmark(pm.id)?.hasNotes ?? false); XCTAssertNil(m.library.bookmark(pm.id)?.notesEditedAt)
        XCTAssertTrue(m.saveNotes(pm.id, "Back again."))
        XCTAssertNotNil(m.library.bookmark(pm.id)?.notesEditedAt)
        // a bookmark that is gone: a notice, nothing saved
        XCTAssertFalse(m.saveNotes(UUID(), "x")); XCTAssertEqual(m.notice?.title, "The notes weren't saved")
    }

    func testTheKeyboardAndTheSearchReachNotes() throws {
        let m = model()
        let pm = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "People Manager" })
        m.query = "avatar"
        XCTAssertEqual(m.hits.map(\.id), [pm.id], "the search covers the notes")
        XCTAssertEqual(m.hits[0].matched, ["notes"])
        m.focusId = pm.id
        XCTAssertEqual(m.focusedBookmark?.id, pm.id)
        // ⇧Space is taken only for a bookmark with notes (the window itself is not opened under xctest)
        let nameless = try XCTUnwrap(m.library.allBookmarks.first { !$0.hasNotes && !$0.hasSecret })
        m.query = ""; m.select(m.library.location(ofBookmark: nameless.id)!); m.focusId = nameless.id
        XCTAssertFalse(m.focusedBookmark?.hasNotes ?? true)
        m.showFocusedNotes()   // nothing to show: no window, no crash
        XCTAssertFalse(NotesWindows.isOpen(nameless.id))
    }

    func testTheWindowFitsItsTextAndQuitIsFreeWithNothingOpen() {
        let screen = NSSize(width: 1440, height: 900)
        let small = NotesWindows.fittedSize(for: "one line", screen: screen)
        XCTAssertEqual(small, NotesWindows.floor, "a short note gets the smallest window")
        let tall = NotesWindows.fittedSize(for: Array(repeating: "a line of notes", count: 40).joined(separator: "\n"), screen: screen)
        XCTAssertEqual(tall.height, (screen.height * 0.7).rounded(.down), "capped at 70% of the screen")
        let wide = NotesWindows.fittedSize(for: String(repeating: "wide ", count: 400), screen: screen)
        XCTAssertEqual(wide.width, (screen.width * 0.6).rounded(.down), "capped at 60% of the screen")
        XCTAssertGreaterThan(wide.height, NotesWindows.floor.height, "a long line wraps into rows")
        XCTAssertTrue(NotesWindows.unsavedIds.isEmpty)
        XCTAssertTrue(NotesWindows.settleBeforeQuit(), "nothing being edited: the quit goes on without a question")
        // addresses inside the notes become links; other words don't
        let linked = NotesText.linked("See https://example.com/page and mail me@example.com, not file:///etc/passwd", muted: false)
        var links: [URL] = []
        linked.enumerateAttribute(.link, in: NSRange(location: 0, length: linked.length)) { v, _, _ in if let u = v as? URL { links.append(u) } }
        XCTAssertEqual(links.map(\.absoluteString), ["https://example.com/page", "mailto:me@example.com"])
    }
}

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

    /// Notes on a directory (Matt, Nov 8 2026): the same window and the same model calls, by the directory's id.
    func testDirectoryNotesGoThroughTheSameModelCalls() throws {
        let m = model()
        let dir = try XCTUnwrap(m.library.allFolders.first { $0.name == "Self-hosted apps" })
        XCTAssertTrue(dir.hasNotes, "the sample has notes on Self-hosted apps")
        let item = try XCTUnwrap(m.notesItem(dir.id))
        XCTAssertTrue(item.isFolder); XCTAssertNil(item.bookmark); XCTAssertEqual(item.name, dir.name); XCTAssertEqual(item.notes, dir.notes); XCTAssertEqual(item.what, "directory")
        XCTAssertTrue(m.saveNotes(dir.id, "Status: everything moved."))
        let saved = try XCTUnwrap(m.library.folder(dir.id))
        XCTAssertEqual(saved.notes, "Status: everything moved."); XCTAssertGreaterThan(saved.notesEditedAt!, dir.notesEditedAt!)
        XCTAssertEqual(try LibraryStore(folder: home).load().folder(dir.id)?.notes, "Status: everything moved.")
        XCTAssertEqual(saved.description, dir.description, "the rest of the directory is untouched"); XCTAssertEqual(saved.bookmarks.count, dir.bookmarks.count)
        // delete: the directory stays, the notes are off
        m.deleteNotes(dir.id)
        let after = try XCTUnwrap(m.library.folder(dir.id))
        XCTAssertFalse(after.hasNotes); XCTAssertEqual(after.notes, ""); XCTAssertNil(after.notesEditedAt); XCTAssertEqual(after.bookmarks.count, dir.bookmarks.count)
        // on again from the editor's side, through updateFolder; a plain rename leaves the notes alone
        m.updateFolder(dir.id, name: after.name, description: after.description, colorId: nil, hasNotes: true, notes: "Back.")
        XCTAssertEqual(m.library.folder(dir.id)?.notes, "Back.")
        m.updateFolder(dir.id, name: "Self-hosted tools", description: after.description, colorId: nil)
        XCTAssertEqual(m.library.folder(dir.id)?.notes, "Back."); XCTAssertEqual(m.library.folder(dir.id)?.name, "Self-hosted tools")
        // the keyboard: the directory's row focused on its parent's page, ⇧Space has notes to show; the search finds them
        m.select(FolderPath(tab: m.library.tabs[0].id)); m.focusId = dir.id
        XCTAssertEqual(m.focusedFolder?.id, dir.id); XCTAssertTrue(m.focusedHasNotes); XCTAssertNil(m.focusedBookmark)
        m.query = "back."
        XCTAssertTrue(m.hits.contains { $0.id == dir.id && $0.isFolder })
        // a new directory with notes typed in the editor
        m.query = ""
        m.addFolder(name: "Photo site", description: "", colorId: nil, hasNotes: true, notes: "Hero photo next.", in: FolderPath(tab: m.library.tabs[0].id))
        let made = try XCTUnwrap(m.library.allFolders.first { $0.name == "Photo site" })
        XCTAssertEqual(made.notes, "Hero photo next."); XCTAssertNotNil(made.notesEditedAt)
        XCTAssertNil(m.notice)
    }

    /// 1.2.1: deleting a directory closes its notes window only once the directory is gone — a refused delete
    /// (it isn't empty) leaves the window, and what is being typed in it, alone. The delete dialog's message
    /// knows a directory that holds nothing but notes.
    func testARefusedDeleteLeavesTheNotesWindowAlone() throws {
        let m = model()
        let dir = try XCTUnwrap(m.library.allFolders.first { $0.name == "Self-hosted apps" })
        XCTAssertFalse(dir.isEmpty, "the sample directory has bookmarks in it")
        NotesWindows.show(folder: dir, model: m)
        XCTAssertTrue(NotesWindows.isOpen(dir.id))
        let holder = try XCTUnwrap(NotesWindows.holder(dir.id))
        holder.editing = true; holder.draft = dir.notes + "\nHalf a thought"
        XCTAssertTrue(holder.isDirty)
        m.deleteFolder(dir.id)
        XCTAssertEqual(m.notice?.title, "The directory wasn't deleted")
        XCTAssertNotNil(m.library.folder(dir.id))
        XCTAssertTrue(NotesWindows.isOpen(dir.id), "the window stays"); XCTAssertEqual(NotesWindows.holder(dir.id)?.draft, holder.draft, "and so does the draft")
        holder.editing = false; holder.draft = dir.notes
        NotesWindows.close(dir.id)
        // a directory with nothing but notes: deletable, and the dialog says the notes go with it
        m.notice = nil
        m.addFolder(name: "Notes only", description: "", colorId: nil, hasNotes: true, notes: "Just a thought.", in: FolderPath(tab: m.library.tabs[0].id))
        let only = try XCTUnwrap(m.library.allFolders.first { $0.name == "Notes only" })
        XCTAssertTrue(only.isEmpty, "nothing inside it, so the Delete… button asks first")
        XCTAssertEqual(only.emptyDeleteMessage, "It has no bookmarks or directories inside it, but it has notes — they are deleted with it.")
        XCTAssertEqual(Folder(name: "Plain").emptyDeleteMessage, "It is empty, so nothing else is lost.")
        NotesWindows.show(folder: only, model: m)
        XCTAssertTrue(NotesWindows.isOpen(only.id))
        m.deleteFolder(only.id)
        XCTAssertNil(m.library.folder(only.id)); XCTAssertNil(m.notice)
        XCTAssertFalse(NotesWindows.isOpen(only.id), "gone with the directory")
    }

    /// Review, Nov 8 2026: an editor that was open while the notes window saved (or the link check took a new
    /// address) saves only what it changed, over the bookmark as it is by then.
    func testAnEditorLaysOnlyItsChangesOverTheBookmarkAsItIsNow() throws {
        let seed = Bookmark(name: "Old name", description: "d", url: "https://old.example/", tags: ["a"], hasNotes: true, notes: "first")
        var now = seed; now.url = "https://new.example/"; now.notes = "saved from the window"; now.notesEditedAt = Date(); now.skipLinkCheck = true
        var edited = seed; edited.name = "New name"; edited.tags = ["a", "b"]
        let merged = now.applyingEdits(edited, since: seed)
        XCTAssertEqual(merged.name, "New name"); XCTAssertEqual(merged.tags, ["a", "b"], "the editor's changes land")
        XCTAssertEqual(merged.url, "https://new.example/"); XCTAssertEqual(merged.notes, "saved from the window"); XCTAssertNotNil(merged.notesEditedAt); XCTAssertTrue(merged.skipLinkCheck, "what changed elsewhere stays")
        // the editor turned the notes off: that wins over the window's save
        var off = seed; off.hasNotes = false; off.notes = ""
        let merged2 = now.applyingEdits(off, since: seed)
        XCTAssertFalse(merged2.hasNotes); XCTAssertEqual(merged2.notes, "")
        // nothing edited at all: the bookmark as it is now, untouched
        XCTAssertEqual(now.applyingEdits(seed, since: seed), now)
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

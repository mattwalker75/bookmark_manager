import XCTest
@testable import BookmarkManagerCore

/// Notes on a bookmark (Matt, Nov 8 2026): plain text, never a secret — in library.json, in every export, found
/// by the search; the last-edited date kept by the library; dropped when the switch is off.
final class NotesTests: XCTestCase {
    func testNotesAreSavedWithTheirDateAndClearedWhenTheSwitchIsOff() throws {
        var lib = Sample.library()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000), t1 = t0.addingTimeInterval(3_600), t2 = t1.addingTimeInterval(3_600)
        var b = Bookmark(name: "Squarespace", url: "https://account.squarespace.com", hasNotes: true, notes: "Where I was: hero photo swapped.")
        try lib.addBookmark(b, in: FolderPath(tab: Sample.work), now: t0)
        XCTAssertEqual(lib.bookmark(b.id)?.notesEditedAt, t0, "new notes get the date they were added")
        // a save that leaves the text alone keeps the date; a changed text gets a new one
        b = lib.bookmark(b.id)!; b.description = "The site"
        try lib.updateBookmark(b, now: t1)
        XCTAssertEqual(lib.bookmark(b.id)?.notesEditedAt, t0)
        b.notes += "\nNext: the contact form."
        try lib.updateBookmark(b, now: t2)
        XCTAssertEqual(lib.bookmark(b.id)?.notesEditedAt, t2)
        // notes switched on with nothing typed yet: allowed (the window says so), no date
        var empty = Bookmark(name: "Later", url: "https://later.example", hasNotes: true)
        try lib.addBookmark(empty, in: FolderPath(tab: Sample.work), now: t0)
        XCTAssertNil(lib.bookmark(empty.id)?.notesEditedAt)
        empty = lib.bookmark(empty.id)!; empty.notes = "now there is text"
        try lib.updateBookmark(empty, now: t1)
        XCTAssertEqual(lib.bookmark(empty.id)?.notesEditedAt, t1)
        // the switch off: text and date go (the editor asks first; the library just does it)
        b.hasNotes = false
        try lib.updateBookmark(b, now: t2)
        let gone = try XCTUnwrap(lib.bookmark(b.id))
        XCTAssertFalse(gone.hasNotes); XCTAssertEqual(gone.notes, ""); XCTAssertNil(gone.notesEditedAt)
        // a secret-only item can have notes too
        let wifi = Bookmark(name: "Wi-Fi", url: "", hasSecret: true, secret: "pw", hasNotes: true, notes: "The router is in the hall closet.")
        try lib.addBookmark(wifi, in: FolderPath(tab: Sample.home), now: t0)
        XCTAssertEqual(lib.bookmark(wifi.id)?.notes, "The router is in the hall closet.")
    }

    func testNotesStayPlainInTheLibraryFileAndEveryExport() throws {
        var lib = Sample.library()
        let b = Bookmark(name: "Squarespace", url: "https://account.squarespace.com", hasSecret: true, secret: "the-password", hasNotes: true, notes: "Billing: Account › Billing › Invoices, NOT Payments.")
        try lib.addBookmark(b, in: FolderPath(tab: Sample.work))
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        try store.save(lib)
        let file = s.read("library.json")
        XCTAssertTrue(file.contains("Billing: Account"), "notes live in library.json as they are")
        XCTAssertFalse(file.contains("the-password"), "the secret still doesn't")
        XCTAssertEqual(try store.load().bookmark(b.id)?.notes, b.notes)
        // an export without secrets still carries the notes; validate is happy with it
        let data = try Transfer.export(lib, includeSecrets: false)
        let back = try Transfer.read(data)
        XCTAssertEqual(back.library.bookmark(b.id)?.notes, b.notes); XCTAssertEqual(back.library.bookmark(b.id)?.secret, "")
        XCTAssertTrue(Transfer.validate(data).canImport)
        // an old file: no notes keys at all
        let old = try JSON.decoder.decode(Bookmark.self, from: Data(#"{"name":"x","url":"https://x.example"}"#.utf8))
        XCTAssertFalse(old.hasNotes); XCTAssertEqual(old.notes, ""); XCTAssertNil(old.notesEditedAt)
        // stray notes text on a bookmark not marked as having notes: a note in Validate, dropped on import
        var stray = lib
        try stray.addBookmark(Bookmark(name: "Stray", url: "https://stray.example", hasNotes: false), in: FolderPath(tab: Sample.work))
        stray.modify(at: FolderPath(tab: Sample.work)) { f in f.bookmarks[f.bookmarks.count - 1].notes = "left over" }
        let report = Transfer.validate(try Transfer.export(stray, includeSecrets: false))
        XCTAssertTrue(report.canImport)
        XCTAssertTrue(report.notes.contains { $0.text.contains("isn't marked as having notes") })
        let imported = Transfer.apply(try Transfer.read(try Transfer.export(stray, includeSecrets: false)), to: Library.fresh(), mode: .replace).library
        XCTAssertEqual(imported.allBookmarks.first { $0.name == "Stray" }?.notes, "")
    }

    /// Notes on a directory (Matt, Nov 8 2026): the same rules as a bookmark's, through addFolder / updateFolder.
    func testNotesOnADirectory() throws {
        var lib = Sample.library()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000), t1 = t0.addingTimeInterval(3_600), t2 = t1.addingTimeInterval(3_600)
        let id = try lib.addFolder(name: "Squarespace site", description: "The photo site", hasNotes: true, notes: "Status: hero photo swapped.", in: FolderPath(tab: Sample.work), now: t0)
        var f = try XCTUnwrap(lib.folder(id))
        XCTAssertTrue(f.hasNotes); XCTAssertEqual(f.notes, "Status: hero photo swapped."); XCTAssertEqual(f.notesEditedAt, t0)
        // a save that leaves the notes alone (nil) keeps text and date; the same text keeps the date; new text gets one
        try lib.updateFolder(id, name: "Squarespace site", description: "Renamed", colorId: nil, now: t1)
        f = try XCTUnwrap(lib.folder(id)); XCTAssertEqual(f.notes, "Status: hero photo swapped."); XCTAssertEqual(f.notesEditedAt, t0); XCTAssertEqual(f.description, "Renamed")
        try lib.updateFolder(id, name: f.name, description: f.description, colorId: nil, hasNotes: true, notes: f.notes, now: t1)
        XCTAssertEqual(lib.folder(id)?.notesEditedAt, t0)
        try lib.updateFolder(id, name: f.name, description: f.description, colorId: nil, hasNotes: true, notes: "Status: done.", now: t2)
        XCTAssertEqual(lib.folder(id)?.notes, "Status: done."); XCTAssertEqual(lib.folder(id)?.notesEditedAt, t2)
        // notes without text: allowed, no date; the switch off: text and date go
        let empty = try lib.addFolder(name: "Later", hasNotes: true, in: FolderPath(tab: Sample.home), now: t0)
        XCTAssertNil(lib.folder(empty)?.notesEditedAt); XCTAssertTrue(lib.folder(empty)?.hasNotes ?? false)
        try lib.updateFolder(id, name: f.name, description: "", colorId: nil, hasNotes: false, notes: "whatever", now: t2)
        let off = try XCTUnwrap(lib.folder(id))
        XCTAssertFalse(off.hasNotes); XCTAssertEqual(off.notes, ""); XCTAssertNil(off.notesEditedAt)
        // a directory without notes: no stray text sneaks in
        try lib.updateFolder(id, name: f.name, description: "", colorId: nil, notes: "typed with the switch off", now: t2)
        XCTAssertEqual(lib.folder(id)?.notes, "")
        // an old file: no notes keys on a directory at all
        let old = try JSON.decoder.decode(Folder.self, from: Data(#"{"name":"Old","folders":[],"bookmarks":[]}"#.utf8))
        XCTAssertFalse(old.hasNotes); XCTAssertEqual(old.notes, ""); XCTAssertNil(old.notesEditedAt)
    }

    func testDirectoryNotesAreExportedSearchedAndTidiedLikeABookmarks() throws {
        var lib = Sample.library()
        let id = try lib.addFolder(name: "Squarespace site", hasNotes: true, notes: "Billing is under Account › Invoices, not Payments.", in: FolderPath(tab: Sample.work))
        // in the file, in the export, back from the export
        let s = Scratch(); let store = LibraryStore(folder: s.url); try store.save(lib)
        XCTAssertTrue(s.read("library.json").contains("Billing is under"))
        XCTAssertEqual(try store.load().folder(id)?.notes, lib.folder(id)?.notes)
        let data = try Transfer.export(lib, includeSecrets: false)
        XCTAssertEqual(try Transfer.read(data).library.folder(id)?.notes, lib.folder(id)?.notes)
        XCTAssertTrue(Transfer.validate(data).canImport)
        // the search finds them, by name and by notes; descriptions still not
        XCTAssertEqual(lib.search("invoices").map(\.id), [id]); XCTAssertEqual(lib.search("invoices")[0].matched, ["notes"])
        XCTAssertEqual(lib.search("squarespace invoices")[0].matched, ["name", "notes"])
        XCTAssertTrue(lib.search("invoices")[0].isFolder)
        XCTAssertFalse(lib.search("logins and health").contains { $0.id == Sample.admin }, "a description is not searched")
        // stray notes on a directory not marked as having notes: a note in Validate, dropped on import
        var stray = lib
        stray.modify(at: FolderPath(tab: Sample.work).appending(Sample.reading)) { $0.notes = "left over" }
        let report = Transfer.validate(try Transfer.export(stray, includeSecrets: false))
        XCTAssertTrue(report.canImport)
        XCTAssertTrue(report.notes.contains { $0.place == "Work › Reading" && $0.text.contains("isn't marked as having notes") })
        let imported = Transfer.apply(try Transfer.read(try Transfer.export(stray, includeSecrets: false)), to: Library.fresh(), mode: .replace).library
        XCTAssertEqual(imported.folder(Sample.reading)?.notes, "")
        XCTAssertFalse(stray.search("left over").contains { $0.id == Sample.reading }, "notes switched off are not searched")
    }

    func testTheSearchFindsNotes() throws {
        var lib = Sample.library()
        let b = Bookmark(name: "Squarespace", url: "https://account.squarespace.com", hasNotes: true, notes: "Still to do: swap the Hero photo, then the Contact form.")
        try lib.addBookmark(b, in: FolderPath(tab: Sample.work))
        let hits = lib.search("hero photo")
        XCTAssertEqual(hits.map(\.id), [b.id]); XCTAssertEqual(hits[0].matched, ["notes"])
        XCTAssertEqual(lib.search("squarespace hero")[0].matched, ["name", "address", "notes"], "every word must be found, in any field")
        XCTAssertTrue(lib.search("contact form").contains { $0.id == b.id })
        // notes switched off are not searched, even if text lingered somehow
        var off = lib
        off.modify(at: FolderPath(tab: Sample.work)) { f in if let i = f.bookmarks.firstIndex(where: { $0.id == b.id }) { f.bookmarks[i].hasNotes = false } }
        XCTAssertFalse(off.search("hero").contains { $0.id == b.id })
    }
}

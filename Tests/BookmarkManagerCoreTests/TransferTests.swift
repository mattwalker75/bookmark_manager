import XCTest
@testable import BookmarkManagerCore

final class TransferTests: XCTestCase {
    func testExportLeavesSecretsOutUnlessAsked() throws {
        let lib = Sample.library()
        let without = try Transfer.export(lib, includeSecrets: false)
        XCTAssertFalse(String(decoding: without, as: UTF8.self).contains("hunter2"))
        let f = try Transfer.read(without)
        XCTAssertFalse(f.secretsIncluded)
        XCTAssertTrue(f.library.bookmark(Sample.postgres)!.hasSecret, "still marked")
        XCTAssertEqual(f.library.bookmark(Sample.postgres)!.secret, "")

        let with = try Transfer.export(lib, includeSecrets: true)
        XCTAssertTrue(String(decoding: with, as: UTF8.self).contains("hunter2"), "decrypted, in plain text, as asked")
        let g = try Transfer.read(with)
        XCTAssertTrue(g.secretsIncluded)
        XCTAssertEqual(g.library, lib)
        XCTAssertEqual(g.app, "Bookmark Manager")
    }

    func testReadRefusesOtherFiles() {
        XCTAssertThrowsBM(try Transfer.read(Data("not json".utf8)), containing: "isn't JSON")
        XCTAssertThrowsBM(try Transfer.read(Data(#"{"a":1}"#.utf8)), containing: "isn't a Bookmark Manager export")
        XCTAssertThrowsBM(try Transfer.read(Data(#"{"app":"App Starter","version":1,"secretsIncluded":false,"library":{"tabs":[]}}"#.utf8)), containing: "from “App Starter”")
        XCTAssertThrowsBM(try Transfer.read(Data(#"{"app":"Bookmark Manager","version":9,"secretsIncluded":false,"library":{"tabs":[]}}"#.utf8)), containing: "newer Bookmark Manager")
    }

    func testValidateIsHappyWithAGoodFile() throws {
        let r = Transfer.validate(try Transfer.export(Sample.library(), includeSecrets: true))
        XCTAssertTrue(r.canImport)
        XCTAssertEqual(r.problems, [])
        XCTAssertEqual(r.tabs, 2); XCTAssertEqual(r.folders, 5); XCTAssertEqual(r.bookmarks, 8); XCTAssertEqual(r.withSecrets, 3)
        XCTAssertEqual(r.counts, "2 tabs, 5 directories, 8 bookmarks (3 with secrets, included).")
    }

    func testValidateNotesSecretsLeftOut() throws {
        let r = Transfer.validate(try Transfer.export(Sample.library(), includeSecrets: false))
        XCTAssertTrue(r.canImport)
        XCTAssertEqual(r.notes.count, 1)
        XCTAssertTrue(r.notes[0].text.contains("3 bookmarks have secrets that are not in this file"))
    }

    func testValidateFindsEveryKindOfProblemWithItsPlace() throws {
        var lib = Sample.library()
        let stray = UUID()
        // a bookmark with no address, a nameless sub-directory, a color that doesn't exist, a bookmark too deep
        lib.modify(at: FolderPath([Sample.work, Sample.vendors])) { f in
            f.bookmarks.append(Bookmark(name: "No address", url: ""))
            f.bookmarks.append(Bookmark(name: "Bad address", url: "two words"))
            f.bookmarks.append(Bookmark(name: "Odd color", url: "https://x.example", colorId: stray))
            f.folders.append(Folder(name: "  ", folders: [Folder(name: "Too deep")]))
        }
        lib.modify(at: FolderPath(tab: Sample.home)) { f in
            f.bookmarks.append(Bookmark(id: Sample.hig, name: "Same id as HIG", url: "https://y.example"))
            f.bookmarks.append(Bookmark(name: "Blank secret", url: "https://z.example", hasSecret: true, secret: ""))
        }
        let r = Transfer.validate(try Transfer.export(lib, includeSecrets: true))
        XCTAssertFalse(r.canImport)
        let places = r.problems.map { "\($0.place): \($0.text)" }
        func has(_ place: String, _ text: String, stops: Bool) {
            let hit = r.problems.first { $0.place == place && $0.text.contains(text) }
            XCTAssertNotNil(hit, "missing “\(place): \(text)” in \(places)")
            if let hit { XCTAssertEqual(hit.stops, stops, place) }
        }
        has("Work › Vendors › No address", "has no address", stops: true)
        has("Work › Vendors › Bad address", "can't be opened", stops: true)
        has("Work › Vendors › Odd color", "color code isn't in the file", stops: false)
        has("Work › Vendors › (no name)", "sub-directory has no name", stops: true)
        has("Work › Vendors › (no name) › Too deep", "3 levels deep, but the file allows 2", stops: true)
        has("Home › Same id as HIG", "id is used twice", stops: true)
        has("Home › Blank secret", "secret is blank", stops: false)
    }

    func testValidateOfRubbish() {
        let r = Transfer.validate(Data("??".utf8))
        XCTAssertFalse(r.canImport)
        XCTAssertEqual(r.problems.count, 1)
        XCTAssertEqual(r.problems[0].place, "The file")
    }

    func testReplaceKeepsLocalSecretsWhenTheFileLeftThemOut() throws {
        let current = Sample.library()
        var edited = current
        try edited.renameTab(Sample.work, "Work (from the other Mac)")
        let file = try Transfer.read(try Transfer.export(edited, includeSecrets: false))
        let (lib, notes) = Transfer.apply(file, to: current, mode: .replace)
        XCTAssertEqual(lib.tab(Sample.work)?.name, "Work (from the other Mac)")
        XCTAssertEqual(lib.bookmark(Sample.postgres)?.secret, "user: admin\npassword: hunter2\n\ntoken: abc")
        XCTAssertEqual(notes, ["3 bookmarks kept the secrets already here."])
        // with secrets in the file, the file wins
        let full = try Transfer.read(try Transfer.export(edited, includeSecrets: true))
        XCTAssertEqual(Transfer.apply(full, to: Library.fresh(), mode: .replace).notes, [])
        // a secret the file doesn't have and we don't either
        let (lib2, notes2) = Transfer.apply(file, to: Library.fresh(), mode: .replace)
        XCTAssertEqual(lib2.bookmark(Sample.postgres)?.secret, "")
        XCTAssertEqual(notes2, ["3 bookmarks need their secrets typed again (the file left them out)."])
    }

    func testAddTabsBringsCopiesWithFreshIds() throws {
        let current = Sample.library()
        let file = try Transfer.read(try Transfer.export(Sample.library(), includeSecrets: true))
        let (lib, notes) = Transfer.apply(file, to: current, mode: .addTabs)
        XCTAssertEqual(lib.tabs.map(\.name), ["Work", "Home", "Work", "Home"])
        XCTAssertEqual(notes, ["Added 2 tabs."])
        let ids = lib.allBookmarks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no id appears twice")
        XCTAssertEqual(lib.tabs[2].allBookmarks.first { $0.name == "Postgres admin" }?.secret, "user: admin\npassword: hunter2\n\ntoken: abc")
        XCTAssertEqual(lib.colors.count, 4, "the same colors (same ids) are not added twice")
    }

    func testAddTabsRaisesDepthAndNotesMissingSecrets() throws {
        var deep = Sample.library()
        try deep.setMaxDepth(3)
        _ = try deep.addFolder(name: "Level 3", in: FolderPath([Sample.work, Sample.selfHosted, Sample.admin]))
        let file = try Transfer.read(try Transfer.export(deep, includeSecrets: false))
        let (lib, notes) = Transfer.apply(file, to: Library.fresh(), mode: .addTabs)
        XCTAssertEqual(lib.maxDepth, 3)
        XCTAssertEqual(lib.tabs.count, 3)
        XCTAssertTrue(notes.contains("Directory levels was raised to 3 to fit the file's directories."))
        XCTAssertTrue(notes.contains("3 bookmarks need their secrets typed again (the file left them out)."))
    }

    func testFreshCopyChangesEveryId() {
        let t = Sample.library().tabs[0]
        let c = Transfer.freshCopy(t)
        XCTAssertNotEqual(c.id, t.id)
        XCTAssertEqual(c.allBookmarks.map(\.name), t.allBookmarks.map(\.name))
        XCTAssertTrue(Set(c.allBookmarks.map(\.id)).isDisjoint(with: t.allBookmarks.map(\.id)))
        XCTAssertTrue(Set(c.allFolders.map(\.id)).isDisjoint(with: t.allFolders.map(\.id)))
    }
}

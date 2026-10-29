import XCTest
@testable import BookmarkManagerCore

/// One test per finding of the Oct 28 2026 core review, so none of them comes back.
final class ReviewFixTests: XCTestCase {
    // 1. a damaged library.json must not cost the secrets on the next save
    func testDamagedLibraryKeepsACopyOfTheSecrets() throws {
        let s = Scratch()
        try LibraryStore(folder: s.url).save(Sample.library())
        try "{ broken".write(toFile: s.file("library.json"), atomically: true, encoding: .utf8)
        let store = LibraryStore(folder: s.url)
        XCTAssertThrowsBM(try store.load(), containing: "and its secrets as secrets.enc.unreadable-")
        // the app goes on with a fresh library and saves something
        var fresh = Library.fresh()
        try fresh.addBookmark(Bookmark(name: "New", url: "https://new.example"), in: FolderPath(tab: fresh.tabs[0].id))
        try store.save(fresh)
        let kept = try FileManager.default.contentsOfDirectory(atPath: s.path).filter { $0.hasPrefix("secrets.enc.unreadable-") }
        XCTAssertEqual(kept.count, 1)
        // putting both files back brings everything back
        let lib = try FileManager.default.contentsOfDirectory(atPath: s.path).first { $0.hasPrefix("library.json.unreadable-") }!
        try FileManager.default.removeItem(atPath: s.file("library.json")); try FileManager.default.removeItem(atPath: s.file("secrets.enc"))
        try FileManager.default.moveItem(atPath: s.file(kept[0]), toPath: s.file("secrets.enc"))
        try "x".write(toFile: s.file(lib), atomically: true, encoding: .utf8)   // (the user "fixes" it: here we just restore a good one)
        try LibraryStore(folder: s.url).save(Sample.library())   // stand-in for the repaired file
        XCTAssertEqual(try LibraryStore(folder: s.url).load().bookmark(Sample.postgres)?.secret, "user: admin\npassword: hunter2\n\ntoken: abc")
    }

    // 2. a save that fails on library.json must not have changed the secrets on disk
    func testHalfSaveLosesNoSecret() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        try store.save(Sample.library())
        var lib = Sample.library()
        lib.deleteBookmark(Sample.postgres)
        // make library.json unwritable: a non-empty directory in its place
        let good = try Data(contentsOf: s.url.appendingPathComponent("library.json"))
        try FileManager.default.removeItem(atPath: s.file("library.json"))
        try FileManager.default.createDirectory(atPath: s.file("library.json"), withIntermediateDirectories: false)
        try "x".write(toFile: s.file("library.json/inside"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.save(lib))
        try FileManager.default.removeItem(atPath: s.file("library.json"))
        try good.write(to: s.url.appendingPathComponent("library.json"))
        XCTAssertEqual(try LibraryStore(folder: s.url).load().bookmark(Sample.postgres)?.secret, "user: admin\npassword: hunter2\n\ntoken: abc")
        // and a good save prunes the secret that nothing needs
        try store.save(lib)
        XCTAssertNil(try store.secrets.load()[Sample.postgres.uuidString])
    }

    // 3. letters that change length when lowercased must not crash the favicon parser
    func testTurkishCapitalIDoesNotBreakTheIconParser() {
        let html = "<html><head><title>İİİİİİİİİİİİ</title><link rel=\"icon\" title=\"İİİİİİİİİİİİ\" href=\"/a.png\"><LINK REL='ICON' href=/b.png/></head>"
        let c = Favicons.candidates(page: URL(string: "https://example.com/")!, html: html).map(\.absoluteString)
        XCTAssertEqual(c, ["https://example.com/a.png", "https://example.com/b.png", "https://example.com/favicon.ico"])
        XCTAssertEqual(Favicons.attribute("href", in: "<link rel=icon href=\"/a.png\" title=\"İİİİ\">"), "/a.png")
    }

    // 4. the app's own export always validates
    func testOwnExportAlwaysValidates() throws {
        var lib = Sample.library()
        XCTAssertThrowsBM(try lib.addColor(name: "  ", rgb: RGB(0, 0, 0)), containing: "color code needs a name")
        XCTAssertThrowsBM(try lib.renameColor(lib.colors[0].id, " "), containing: "needs a name")
        // a file whose levels setting is below what it holds is repaired on load
        let s = Scratch()
        var low = Sample.library(); low.maxDepth = 1
        try JSON.encoder.encode(LibraryFile(library: low)).write(to: s.url.appendingPathComponent("library.json"))
        let loaded = try LibraryStore(folder: s.url).load()
        XCTAssertEqual(loaded.maxDepth, 2)
        XCTAssertTrue(Transfer.validate(try Transfer.export(loaded, includeSecrets: false)).canImport)
        var deep = Sample.library(); deep.maxDepth = 99
        try JSON.encoder.encode(LibraryFile(library: deep)).write(to: s.url.appendingPathComponent("library.json"))
        XCTAssertEqual(try LibraryStore(folder: s.url).load().maxDepth, 2)
    }

    // 5. a repeated id is repaired on load and refused when adding
    func testRepeatedIdsAreRepaired() throws {
        var lib = Sample.library()
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(id: Sample.hig, name: "Twin", url: "https://t.example"), in: FolderPath(tab: Sample.home)), containing: "already in the library")
        lib.modify(at: FolderPath(tab: Sample.home)) { $0.bookmarks.append(Bookmark(id: Sample.hig, name: "Twin", url: "https://t.example", hasSecret: true, secret: "B")) }
        let s = Scratch()
        try JSON.encoder.encode(LibraryFile(library: lib)).write(to: s.url.appendingPathComponent("library.json"))
        let loaded = try LibraryStore(folder: s.url).load()
        let ids = loaded.allBookmarks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(loaded.allBookmarks.filter { $0.name == "Twin" }.count, 1)
        // and in an import
        let file = try Transfer.read(try Transfer.export(lib, includeSecrets: true))
        let (imported, notes) = Transfer.apply(file, to: Library.fresh(), mode: .replace)
        XCTAssertEqual(Set(imported.allBookmarks.map(\.id)).count, imported.allBookmarks.count)
        XCTAssertTrue(notes.contains { $0.contains("already used") }, "\(notes)")
    }

    // 6. a drop onto the directory it is already in changes nothing
    func testDropOntoOwnDirectoryKeepsTheOrder() throws {
        var lib = Sample.library()
        try lib.move(.folder(Sample.selfHosted), to: FolderPath(tab: Sample.work))
        try lib.move(.bookmark(Sample.peopleManager), to: FolderPath([Sample.work, Sample.selfHosted]))
        XCTAssertEqual(lib, Sample.library())
    }

    // 7. case and accents don't matter
    func testSearchIgnoresCaseAndAccents() throws {
        var lib = Sample.library()
        try lib.addBookmark(Bookmark(name: "İstanbul café guide", url: "https://x.example"), in: FolderPath(tab: Sample.home))
        XCTAssertEqual(lib.search("istanbul cafe").map(\.name), ["İstanbul café guide"])
        XCTAssertEqual(lib.search("ISTANBUL").count, 1)
    }

    // 8. odd but harmless fields don't make the file "not an export"; a wrong shape says where
    func testReadIsLenientAndNamesThePlace() throws {
        let base = #""secretsIncluded":false,"library":{"tabs":[{"name":"T","bookmarks":[{"name":"B","url":"https://b.example"}]}]}"#
        XCTAssertNoThrow(try Transfer.read(Data((#"{"app":"Bookmark Manager","version":1,"exportedAt":"2026-10-28","# + base + "}").utf8)))
        XCTAssertNoThrow(try Transfer.read(Data((#"{"app":"Bookmark Manager","version":"1","exportedAt":"2026-10-28T10:00:00.123Z","# + base + "}").utf8)))
        let bad = #"{"app":"Bookmark Manager","version":1,"secretsIncluded":false,"library":{"tabs":[{"name":"T","bookmarks":[{"name":"B","url":"https://b.example","tags":"a, b"}]}]}}"#
        XCTAssertThrowsBM(try Transfer.read(Data(bad.utf8)), containing: "library › tabs › item 1 › bookmarks › item 1 › tags")
    }

    // 9. the secrets messages don't ask the user to move a file the app already moved
    func testSecretMessagesDoNotAskToMoveFiles() throws {
        let s = Scratch()
        try LibraryStore(folder: s.url).save(Sample.library())
        try FileManager.default.removeItem(atPath: s.file("secret.key"))
        let store = LibraryStore(folder: s.url)
        _ = try store.load()
        XCTAssertFalse(store.problem!.contains("Move "), store.problem!)
        XCTAssertTrue(store.problem!.contains("kept as secrets.enc.unreadable-"))
    }

    // 10. the refusal counts what the person sees
    func testEmptyCheckCountsDirectDirectories() throws {
        var lib = Sample.library()
        XCTAssertThrowsBM(try lib.deleteTab(Sample.work), containing: "7 bookmarks and 3 directories")
    }

    // 11. no "format.)." in the damaged-file sentence
    func testDamagedFileSentenceReadsWell() throws {
        let s = Scratch()
        try "{ broken".write(toFile: s.file("library.json"), atomically: true, encoding: .utf8)
        do { _ = try LibraryStore(folder: s.url).load(); XCTFail() } catch let e as BMError {
            XCTAssertFalse(e.message.contains(".)."), e.message)
            XCTAssertTrue(e.message.contains("could not be read: "), e.message)
        }
    }

    // 12. data: hrefs are skipped; names() of a bad path is empty
    func testCandidatesAndNamesEdges() {
        let c = Favicons.candidates(page: URL(string: "https://example.com/")!, html: "<link rel=icon href=\"data:image/png;base64,AAAA\">").map(\.absoluteString)
        XCTAssertEqual(c, ["https://example.com/favicon.ico"])
        XCTAssertEqual(Sample.library().names(FolderPath([Sample.work, UUID()])), [])
    }

    // 13. replace trusts the file's flag, not stray secret text
    func testReplaceBlanksSecretsWhenTheFileSaysNone() throws {
        var file = try Transfer.read(try Transfer.export(Sample.library(), includeSecrets: true))
        file.secretsIncluded = false
        let (lib, _) = Transfer.apply(file, to: Library.fresh(), mode: .replace)
        XCTAssertEqual(lib.allBookmarks.filter(\.hasSecret).map(\.secret), ["", "", ""])
    }
}

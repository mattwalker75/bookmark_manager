import XCTest
@testable import BookmarkManagerCore

final class ModelsTests: XCTestCase {
    func testFreshLibraryHasOneTabAndFourColors() {
        let lib = Library.fresh()
        XCTAssertEqual(lib.tabs.count, 1)
        XCTAssertEqual(lib.tabs[0].name, "Bookmarks")
        XCTAssertEqual(lib.colors.map(\.name), ["Important", "Work", "Personal", "Reference"])
        XCTAssertEqual(lib.maxDepth, 2)
    }

    func testPathsAndNames() throws {
        let lib = Sample.library()
        let p = try XCTUnwrap(lib.location(ofBookmark: Sample.postgres))
        XCTAssertEqual(p.ids, [Sample.work, Sample.selfHosted, Sample.admin])
        XCTAssertEqual(lib.names(p), ["Work", "Self-hosted apps", "Admin pages"])
        XCTAssertEqual(p.depth, 2)
        XCTAssertEqual(lib.path(toFolder: Sample.vendors)?.ids, [Sample.work, Sample.vendors])
        XCTAssertEqual(lib.path(toFolder: Sample.work)?.ids, [Sample.work])
        XCTAssertEqual(lib.folder(at: FolderPath([Sample.work, Sample.selfHosted]))?.name, "Self-hosted apps")
        XCTAssertNil(lib.folder(at: FolderPath([Sample.home, Sample.selfHosted])))
        XCTAssertEqual(lib.bookmark(Sample.webull)?.name, "Webull")
        XCTAssertEqual(lib.deepestLevel, 2)
        XCTAssertTrue(FolderPath([Sample.work, Sample.selfHosted, Sample.admin]).isInside(FolderPath([Sample.work, Sample.selfHosted])))
        XCTAssertFalse(FolderPath([Sample.work, Sample.vendors]).isInside(FolderPath([Sample.work, Sample.selfHosted])))
    }

    func testTabsNeedANameAndTheLastOneStays() throws {
        var lib = Library.fresh()
        XCTAssertThrowsBM(try lib.addTab("   "), containing: "needs a name")
        let only = lib.tabs[0].id
        XCTAssertThrowsBM(try lib.deleteTab(only), containing: "only tab")
        let second = try lib.addTab("  Home ")
        XCTAssertEqual(lib.tab(second)?.name, "Home")
        try lib.renameTab(second, "House")
        XCTAssertEqual(lib.tab(second)?.name, "House")
        try lib.deleteTab(second)
        XCTAssertEqual(lib.tabs.count, 1)
        // a tab with something in it stays
        try lib.addBookmark(Bookmark(name: "A", url: "https://a.example"), in: FolderPath(tab: only))
        _ = try lib.addTab("Other")
        XCTAssertThrowsBM(try lib.deleteTab(only), containing: "still has 1 bookmark")
    }

    func testMoveTabChangesOrder() throws {
        var lib = Sample.library()
        lib.moveTab(Sample.home, to: 0)
        XCTAssertEqual(lib.tabs.map(\.name), ["Home", "Work"])
        lib.moveTab(Sample.home, to: 5)
        XCTAssertEqual(lib.tabs.map(\.name), ["Work", "Home"])
    }

    func testDirectoriesGoOnlyAsDeepAsAllowed() throws {
        var lib = Sample.library()
        let adminPath = FolderPath([Sample.work, Sample.selfHosted, Sample.admin])
        XCTAssertThrowsBM(try lib.addFolder(name: "Too deep", in: adminPath), containing: "3 levels deep")
        try lib.setMaxDepth(3)
        let deep = try lib.addFolder(name: "Deeper", description: " notes ", in: adminPath)
        XCTAssertEqual(lib.folder(deep)?.description, "notes")
        XCTAssertEqual(lib.deepestLevel, 3)
        // can't lower it below what exists
        XCTAssertThrowsBM(try lib.setMaxDepth(2), containing: "3 levels down")
        try lib.deleteFolder(deep)
        try lib.setMaxDepth(2)
        XCTAssertThrowsBM(try lib.setMaxDepth(0), containing: "between 1 and 6")
        XCTAssertThrowsBM(try lib.setMaxDepth(7), containing: "between 1 and 6")
    }

    func testDeletingADirectoryNeedsItEmpty() throws {
        var lib = Sample.library()
        XCTAssertThrowsBM(try lib.deleteFolder(Sample.selfHosted), containing: "still has 4 bookmarks and 1 directory")
        XCTAssertThrowsBM(try lib.deleteFolder(Sample.admin), containing: "sub-directory can only be deleted once it is empty")
        lib.deleteBookmark(Sample.postgres); lib.deleteBookmark(Sample.routerStatus)
        try lib.deleteFolder(Sample.admin)
        XCTAssertNil(lib.folder(Sample.admin))
        XCTAssertEqual(lib.folder(Sample.selfHosted)?.folders.count, 0)
    }

    func testBookmarksAreCleanedAndChecked() throws {
        var lib = Library.fresh()
        let tab = FolderPath(tab: lib.tabs[0].id)
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(name: " ", url: "https://x.example"), in: tab), containing: "needs a name")
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(name: "X", url: ""), in: tab), containing: "needs an address, or a secret")
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(name: "X", url: "not an address"), in: tab), containing: "doesn't look like an address")
        var b = Bookmark(name: "  Example ", description: " d ", url: " example.com/page ", tags: Bookmark.parseTags("a, b,,A ,c"), hasSecret: false, secret: "leftover")
        try lib.addBookmark(b, in: tab)
        let saved = try XCTUnwrap(lib.bookmark(b.id))
        XCTAssertEqual(saved.name, "Example")
        XCTAssertEqual(saved.description, "d")
        XCTAssertEqual(saved.url, "example.com/page")
        XCTAssertEqual(saved.link?.absoluteString, "https://example.com/page")
        XCTAssertEqual(saved.tags, ["a", "b", "c"])
        XCTAssertEqual(saved.secret, "", "no secret unless the box is ticked")
        b.hasSecret = true; b.secret = "line 1\n\nline 3"
        try lib.updateBookmark(b)
        XCTAssertEqual(lib.bookmark(b.id)?.secret, "line 1\n\nline 3")
        // put before another one
        let first = Bookmark(name: "First", url: "https://first.example")
        try lib.addBookmark(first, in: tab, before: b.id)
        XCTAssertEqual(lib.tabs[0].bookmarks.map(\.name), ["First", "Example"])
        lib.sortByName(at: tab)
        XCTAssertEqual(lib.tabs[0].bookmarks.map(\.name), ["Example", "First"])
    }

    func testLinks() {
        XCTAssertEqual(Bookmark.link(from: "github.com")?.absoluteString, "https://github.com")
        XCTAssertEqual(Bookmark.link(from: "http://192.168.1.1:8080/x")?.host, "192.168.1.1")
        XCTAssertEqual(Bookmark.link(from: "mailto:a@b.c")?.scheme, "mailto")
        XCTAssertNil(Bookmark.link(from: "two words"))
        XCTAssertNil(Bookmark.link(from: "https://"))
        XCTAssertNil(Bookmark.link(from: ""))
    }

    func testColorCodes() throws {
        var lib = Sample.library()
        let important = lib.colors[0].id
        XCTAssertEqual(lib.uses(ofColor: important).bookmarks, 2)
        lib.removeColor(important)
        XCTAssertEqual(lib.colors.count, 3)
        XCTAssertNil(lib.bookmark(Sample.postgres)?.colorId)
        XCTAssertNil(lib.bookmark(Sample.webull)?.colorId)
        for i in lib.colors.count..<ColorCode.maximum { _ = try lib.addColor(name: "C\(i)", rgb: RGB(0, 0, 0)) }
        XCTAssertThrowsBM(try lib.addColor(name: "One too many", rgb: RGB(0, 0, 0)), containing: "at most 10")
    }

    func testOldFilesStillDecode() throws {
        // a file with only the essentials: everything else takes its default
        let json = #"{"tabs":[{"name":"T","bookmarks":[{"name":"B","url":"https://b.example"}]}]}"#
        let lib = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(lib.maxDepth, 2)
        XCTAssertEqual(lib.colors.count, 4)
        XCTAssertEqual(lib.tabs[0].bookmarks[0].tags, [])
        XCTAssertFalse(lib.tabs[0].bookmarks[0].hasSecret)
    }

    func testLevelNames() {
        XCTAssertEqual(Library.levelName(1), "directory")
        XCTAssertEqual(Library.levelName(2), "sub-directory")
        XCTAssertEqual(Library.levelName(3), "level-3 directory")
    }
}

/// Secret-only items (Matt, Oct 29 2026): a bookmark with no address at all, kept in the same list as the others.
final class SecretOnlyTests: XCTestCase {
    func testASecretWithoutAnAddressIsAllowedAndOnlyThen() throws {
        var lib = Library.fresh()
        let tab = FolderPath(tab: lib.tabs[0].id)
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(name: "Nothing", url: "   "), in: tab), containing: "needs an address, or a secret")
        let s = Bookmark(name: "Wi-Fi password", url: "  ", hasSecret: true, secret: "guest: MintyFresh")
        try lib.addBookmark(s, in: tab)
        let saved = try XCTUnwrap(lib.bookmark(s.id))
        XCTAssertTrue(saved.isSecretOnly)
        XCTAssertEqual(saved.url, "", "blanks are trimmed away")
        XCTAssertNil(saved.link)
        XCTAssertEqual(saved.secret, "guest: MintyFresh")
        // typing an address later turns it back into an ordinary bookmark
        var edited = saved; edited.url = "router.lan"
        try lib.updateBookmark(edited)
        XCTAssertFalse(try XCTUnwrap(lib.bookmark(s.id)).isSecretOnly)
        // and taking the secret away from a secret-only item is refused (it would be an empty row)
        var bare = saved; bare.hasSecret = false
        XCTAssertThrowsBM(try lib.updateBookmark(bare), containing: "needs an address, or a secret")
    }

    func testSecretOnlyItemsAreFoundSavedAndExported() throws {
        var lib = Sample.library()
        let s = Bookmark(name: "Backup passphrase", url: "", tags: ["restic"], hasSecret: true, secret: "correct-horse")
        try lib.addBookmark(s, in: FolderPath(tab: Sample.work))
        XCTAssertEqual(lib.search("passphrase").map(\.name), ["Backup passphrase"])
        XCTAssertEqual(lib.search("restic").map(\.name), ["Backup passphrase"])
        let scratch = Scratch()
        let store = LibraryStore(folder: scratch.url)
        try store.save(lib)
        let back = try XCTUnwrap(try store.load().bookmark(s.id))
        XCTAssertTrue(back.isSecretOnly); XCTAssertEqual(back.secret, "correct-horse")
        // an export without secrets: validation is still happy (no address is fine when it is a secret)
        let r = Transfer.validate(try Transfer.export(lib, includeSecrets: false))
        XCTAssertTrue(r.canImport, r.problems.map(\.text).joined(separator: " / "))
        XCTAssertFalse(r.problems.contains { $0.text.contains("no address") })
        // replacing from that file keeps the local secret by id
        let (imported, _) = Transfer.apply(try Transfer.read(try Transfer.export(lib, includeSecrets: false)), to: lib, mode: .replace)
        XCTAssertEqual(imported.bookmark(s.id)?.secret, "correct-horse")
    }
}

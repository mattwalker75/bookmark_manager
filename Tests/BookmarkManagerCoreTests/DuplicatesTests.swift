import XCTest
@testable import BookmarkManagerCore

/// Duplicate bookmarks (Matt, Nov 8 2026): how addresses are compared, how groups are made, and how a group
/// marked as meant to be the same drops out.
final class DuplicatesTests: XCTestCase {
    func testTheSamePageWrittenDifferentlyGetsOneKey() {
        let k = Library.duplicateKey
        XCTAssertEqual(k("https://www.Example.com/a/b/"), "example.com/a/b")
        XCTAssertEqual(k("http://example.com/a/b"), "example.com/a/b", "http and https, www or not, a trailing slash: one page")
        XCTAssertEqual(k("example.com/a/b#section"), "example.com/a/b", "a fragment is the same page")
        XCTAssertEqual(k("https://example.com:443/a/b"), "example.com/a/b", "a default port is no port")
        XCTAssertEqual(k("https://example.com:8443/a/b"), "example.com:8443/a/b", "another port is another server")
        XCTAssertEqual(k("https://example.com/"), "example.com/"); XCTAssertEqual(k("https://example.com"), "example.com/")
        XCTAssertEqual(k("https://example.com/A/B"), "example.com/A/B", "the path keeps its case (servers care)")
        XCTAssertEqual(k("https://shop.example/item?id=7&utm_source=news&fbclid=xyz&UTM_Medium=mail"), "shop.example/item?id=7", "tracking names drop, the real query stays")
        XCTAssertEqual(k("https://shop.example/item?b=2&a=1"), k("https://shop.example/item?a=1&b=2"), "query order doesn't matter")
        XCTAssertNotEqual(k("https://shop.example/item?id=7"), k("https://shop.example/item?id=8"), "a different query is a different page")
        XCTAssertNotEqual(k("https://github.com/x?ref=main"), k("https://github.com/x"), "ref is not a tracking name")
        XCTAssertEqual(k("mailto:Someone@Example.com"), "mailto:someone@example.com", "other kinds of address compare as typed, in lower case")
        XCTAssertNil(k(""), "a secret-only item has no address to compare"); XCTAssertNil(k("   ")); XCTAssertNil(k("two words")); XCTAssertNil(k("javascript:alert(1)"))
    }

    private func library() -> Library {
        var lib = Sample.library()
        // Pull requests twice (written differently) in Dev, Gmail three times across tabs (letter for letter), a lone one
        let dev = Folder(name: "Dev", bookmarks: [
            Bookmark(name: "Pull requests", url: "https://github.com/pulls"),
            Bookmark(name: "PRs (old link)", url: "http://www.github.com/pulls/?utm_source=mail"),
            Bookmark(name: "Swift forums", url: "https://forums.swift.org"),
        ])
        lib.tabs.append(dev)
        try! lib.addBookmark(Bookmark(name: "Gmail · work", url: "https://mail.google.com/mail/u/0/"), in: FolderPath(tab: Sample.work))
        try! lib.addBookmark(Bookmark(name: "Gmail · home", url: "https://mail.google.com/mail/u/0/"), in: FolderPath(tab: Sample.home))
        try! lib.addBookmark(Bookmark(name: "Gmail · family", url: "https://mail.google.com/mail/u/0/"), in: FolderPath([Sample.home, Sample.network]))
        return lib
    }

    func testGroupsAreMadeInLibraryOrderWithExactAndNotExact() {
        let lib = library()
        let r = lib.findDuplicates()
        XCTAssertEqual(r.groups.count, 2)
        XCTAssertEqual(r.checked, lib.allBookmarks.filter { !$0.isSecretOnly }.count)
        let gmail = r.groups[0], prs = r.groups[1]
        XCTAssertEqual(gmail.key, "mail.google.com/mail/u/0"); XCTAssertTrue(gmail.exact); XCTAssertEqual(gmail.bookmarkIds.count, 3)
        XCTAssertEqual(lib.bookmark(gmail.bookmarkIds[0])?.name, "Gmail · work", "the Work tab comes first in the library")
        XCTAssertEqual(prs.key, "github.com/pulls"); XCTAssertFalse(prs.exact, "written differently"); XCTAssertEqual(prs.bookmarkIds.count, 2)
        XCTAssertFalse(gmail.allKept); XCTAssertFalse(prs.allKept)
        XCTAssertEqual(r.shown.count, 2); XCTAssertEqual(r.shownBookmarks, 5); XCTAssertEqual(r.keptAway.count, 0)
        XCTAssertEqual(r.summary, "2 groups of bookmarks point at the same page — 5 bookmarks in all")
        XCTAssertEqual(Library.fresh().findDuplicates().summary, "No two bookmarks point at the same page.")
        XCTAssertEqual(DuplicateReport(groups: [prs], checked: 2).summary, "1 group of bookmarks points at the same page — 2 bookmarks in all")
    }

    func testAGroupMarkedAsMeantToBeTheSameDropsOutUntilANewMemberArrives() throws {
        var lib = library()
        let gmail = lib.findDuplicates().groups[0]
        lib.setKeptAsDuplicates(gmail.bookmarkIds, true)
        var r = lib.findDuplicates()
        XCTAssertEqual(r.shown.count, 1, "only the PRs group is listed now")
        XCTAssertEqual(r.keptAway.count, 1); XCTAssertEqual(r.keptAwayBookmarks, 3)
        XCTAssertTrue(r.groups[0].allKept, "the group is still there, for 'show the ones left out'")
        XCTAssertTrue(lib.allBookmarks.filter { $0.name.hasPrefix("Gmail") }.allSatisfy(\.skipDuplicateCheck))
        // a fourth Gmail bookmark added by accident later: the group comes back, with the three marked ones in it
        try lib.addBookmark(Bookmark(name: "Gmail again", url: "https://mail.google.com/mail/u/0"), in: FolderPath(tab: Sample.work))
        r = lib.findDuplicates()
        XCTAssertEqual(r.shown.count, 2); XCTAssertEqual(r.shown[0].bookmarkIds.count, 4); XCTAssertFalse(r.shown[0].allKept)
        // taking the mark off brings a group back as it was; a bookmark that is gone is skipped without complaint
        lib.setKeptAsDuplicates(gmail.bookmarkIds + [UUID()], false)
        XCTAssertFalse(lib.allBookmarks.contains(where: \.skipDuplicateCheck))
    }

    func testTheMarkIsSavedExportedAndReadWithADefault() throws {
        var lib = library()
        let id = lib.findDuplicates().groups[0].bookmarkIds[0]
        lib.setKeptAsDuplicates([id], true)
        let data = try Transfer.export(lib, includeSecrets: false)
        let back = try Transfer.read(data).library
        XCTAssertTrue(back.bookmark(id)?.skipDuplicateCheck ?? false, "an export carries the mark")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"skipDuplicateCheck\" : true"))
        let old = try JSON.decoder.decode(Bookmark.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"x","url":"https://x.example"}"#.utf8))
        XCTAssertFalse(old.skipDuplicateCheck, "a file from before reads with the default")
        let odd = try JSON.decoder.decode(Bookmark.self, from: Data(#"{"name":"x","url":"https://x.example","skipDuplicateCheck":"yes"}"#.utf8))
        XCTAssertFalse(odd.skipDuplicateCheck, "a wrongly typed value is forgiven")
        // the library file keeps it too
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        try store.save(lib)
        XCTAssertTrue(try store.load().bookmark(id)?.skipDuplicateCheck ?? false)
    }
}

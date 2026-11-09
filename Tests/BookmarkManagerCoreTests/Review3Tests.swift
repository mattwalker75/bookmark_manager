import XCTest
@testable import BookmarkManagerCore

/// The deep review of Nov 8 2026 (five reviewers), core side: each case asserts the fixed behaviour.
final class Review3Tests: XCTestCase {
    func testAnUpperCaseSchemeGetsTheSameHostCheck() {
        XCTAssertNil(Bookmark.link(from: "HTTPS://"), "no host: refused like https://")
        XCTAssertNil(Bookmark.link(from: "Https://"))
        XCTAssertEqual(Bookmark.link(from: "HTTPS://x.example/page")?.host, "x.example")
        var lib = Library.fresh()
        XCTAssertThrowsBM(try lib.addBookmark(Bookmark(name: "x", url: "HTTP://"), in: FolderPath(tab: lib.tabs[0].id)), containing: "address")
    }

    func testValidateUsesTheLibrarysBlankRule() throws {
        for ch in ["\u{3164}", "\u{FEFF}", "\u{2060}", "\u{00AD}"] {
            var lib = Library.fresh()
            lib.tabs[0].folders = [Folder(name: ch, bookmarks: [Bookmark(name: "ok", url: "https://a.example/")])]
            lib.tabs[0].bookmarks = [Bookmark(name: ch, url: "https://b.example/")]
            lib.colors = [ColorCode(name: ch, rgb: RGB(0.5, 0.5, 0.5))]
            let r = Transfer.validate(try Transfer.export(lib, includeSecrets: false))
            XCTAssertFalse(r.canImport, "U+\(String(format: "%04X", ch.unicodeScalars.first!.value)) is no name")
            XCTAssertTrue(r.problems.contains { $0.text == "This directory has no name." }); XCTAssertTrue(r.problems.contains { $0.text == "This bookmark has no name." })
            XCTAssertTrue(r.problems.contains { $0.text == "A color code has no name." })
        }
        XCTAssertTrue(Library.isBlank(" \u{200B}\u{3164} ")); XCTAssertFalse(Library.isBlank(" a "))
    }

    func testADamagedSecretsFileKeepsAGoodKey() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        var lib = Library.fresh()
        _ = try lib.addBookmark(Bookmark(name: "With secret", url: "https://a.example/", hasSecret: true, secret: "hunter2"), in: FolderPath(tab: lib.tabs[0].id))
        try store.save(lib)
        let keyBefore = try Data(contentsOf: store.secrets.keyURL)
        try Data("not sealed at all".utf8).write(to: store.secrets.dataURL)
        let again = LibraryStore(folder: s.url)
        let loaded = try again.load()
        XCTAssertEqual(loaded.allBookmarks.first?.secret, "", "the secrets are gone for now")
        let problem = try XCTUnwrap(again.problem)
        XCTAssertTrue(problem.contains("secrets.enc.unreadable-")); XCTAssertFalse(problem.contains("secret.key.unreadable-"), "the key was not retired")
        XCTAssertTrue(problem.contains("backups still open"))
        XCTAssertEqual(try Data(contentsOf: store.secrets.keyURL), keyBefore, "the same key is still in place")
        XCTAssertNotNil(try again.secrets.currentKey())
        // a damaged KEY still moves both aside (the secrets file is written again first — the load above moved it)
        try again.save(loaded)
        try Data("short".utf8).write(to: store.secrets.keyURL)
        let third = LibraryStore(folder: s.url); _ = try third.load()
        XCTAssertTrue(third.problem?.contains("secret.key.unreadable-") ?? false)
    }

    func testFirefoxTagsAreDecoded() throws {
        let html = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p><DT><A HREF=\"https://a.example/\" TAGS=\"R&amp;D,caf&#233;,work\">A</A></DL>"
        let f = try BrowserBookmarks.parse(Data(html.utf8))
        XCTAssertEqual(f.root.links[0].tags, ["R&D", "café", "work"])
    }
}

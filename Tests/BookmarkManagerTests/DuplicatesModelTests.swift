import XCTest
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// The duplicates sheet's model side (Matt, Nov 8 2026): the report from the library as it is, the mark saved
/// to disk, the editor's switch undoing it, a deleted bookmark leaving its group.
@MainActor
final class DuplicatesModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-dups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel {
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        // the app's sample already holds two groups (Gmail twice, Pull requests twice); a third pair of its own
        var lib = Sample.library()
        try! lib.addBookmark(Bookmark(name: "HIG again", url: "http://www.developer.apple.com/design/human-interface-guidelines/"), in: FolderPath(tab: lib.tabs[1].id))
        m.importFileForTest(lib)
        return m
    }

    func testTheMarkIsSavedAndTheGroupLeavesTheSheet() throws {
        let m = model()
        XCTAssertEqual(m.duplicates.shown.count, 3)
        let gmail = try XCTUnwrap(m.duplicates.groups.first { $0.exact })
        XCTAssertEqual(gmail.key, "mail.google.com/mail/u/0")
        m.keepDuplicates(gmail.bookmarkIds, true)
        XCTAssertEqual(m.duplicates.shown.count, 2); XCTAssertEqual(m.duplicates.keptAway.count, 1)
        XCTAssertNil(m.notice)
        // on disk too
        let again = try LibraryStore(folder: home).load()
        XCTAssertTrue(gmail.bookmarkIds.allSatisfy { again.bookmark($0)?.skipDuplicateCheck ?? false })
        // the editor's switch takes one bookmark's mark off: the group is listed again, with the other still marked
        var b = try XCTUnwrap(m.library.bookmark(gmail.bookmarkIds[0]))
        b.skipDuplicateCheck = false
        m.updateBookmark(b)
        XCTAssertEqual(m.duplicates.shown.count, 3)
        XCTAssertTrue(m.library.bookmark(gmail.bookmarkIds[1])?.skipDuplicateCheck ?? false)
        // "Look at these again" clears every member
        m.keepDuplicates(gmail.bookmarkIds, false)
        XCTAssertFalse(m.library.allBookmarks.contains(where: \.skipDuplicateCheck))
    }

    func testADeletedBookmarkLeavesItsGroupAndTheMenuSheetOpens() throws {
        let m = model()
        let hig = try XCTUnwrap(m.duplicates.groups.first { $0.key.hasPrefix("developer.apple.com") })
        XCTAssertFalse(hig.exact); XCTAssertEqual(hig.bookmarkIds.count, 2)
        m.deleteBookmark(hig.bookmarkIds[1])
        XCTAssertEqual(m.duplicates.shown.count, 2, "a page with one bookmark left is no duplicate")
        m.sheet = .duplicates
        XCTAssertEqual(m.sheet?.id, "duplicates")
        // the marks survive an export and come back with an import
        for g in m.duplicates.shown { m.keepDuplicates(g.bookmarkIds, true) }
        let data = try m.exportData(includeSecrets: false)
        let f = try Transfer.read(data)
        XCTAssertEqual(f.library.allBookmarks.filter(\.skipDuplicateCheck).count, 4)
        _ = m.importFile(f, mode: .replace)
        XCTAssertEqual(m.duplicates.shown.count, 0); XCTAssertEqual(m.duplicates.keptAwayBookmarks, 4)
    }
}

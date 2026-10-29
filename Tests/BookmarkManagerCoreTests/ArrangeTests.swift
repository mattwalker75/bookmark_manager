import XCTest
@testable import BookmarkManagerCore

final class ArrangeTests: XCTestCase {
    func testTokensRoundTrip() {
        let id = UUID()
        XCTAssertEqual(DragItem(token: DragItem.bookmark(id).token), .bookmark(id))
        XCTAssertEqual(DragItem(token: DragItem.folder(id).token), .folder(id))
        XCTAssertNil(DragItem(token: "nonsense"))
        XCTAssertNil(DragItem(token: "bookmark:not-a-uuid"))
    }

    func testBookmarkMovesBetweenDirectoriesAndTabs() throws {
        var lib = Sample.library()
        let vendors = FolderPath([Sample.work, Sample.vendors])
        try lib.move(.bookmark(Sample.postgres), to: vendors)
        XCTAssertEqual(lib.location(ofBookmark: Sample.postgres), vendors)
        XCTAssertEqual(lib.folder(at: vendors)?.bookmarks.map(\.name), ["Webull", "Postgres admin"])
        XCTAssertEqual(lib.bookmark(Sample.postgres)?.secret, "user: admin\npassword: hunter2\n\ntoken: abc", "the secret travels with it")
        // before another one, in the same list
        try lib.move(.bookmark(Sample.postgres), to: vendors, before: Sample.webull)
        XCTAssertEqual(lib.folder(at: vendors)?.bookmarks.map(\.name), ["Postgres admin", "Webull"])
        // onto a tab's top level
        try lib.move(.bookmark(Sample.webull), to: FolderPath(tab: Sample.home))
        XCTAssertEqual(lib.tab(Sample.home)?.bookmarks.map(\.name), ["Webull"])
        // before itself = nothing happens
        try lib.move(.bookmark(Sample.webull), to: FolderPath(tab: Sample.home), before: Sample.webull)
        XCTAssertEqual(lib.tab(Sample.home)?.bookmarks.count, 1)
    }

    func testDirectoryMovesWithEverythingInIt() throws {
        var lib = Sample.library()
        try lib.move(.folder(Sample.selfHosted), to: FolderPath(tab: Sample.home))
        XCTAssertEqual(lib.tab(Sample.work)?.folders.map(\.name), ["Vendors", "Reading"])
        XCTAssertEqual(lib.tab(Sample.home)?.folders.map(\.name), ["Network", "Self-hosted apps"])
        XCTAssertEqual(lib.location(ofBookmark: Sample.postgres)?.ids, [Sample.home, Sample.selfHosted, Sample.admin])
        // reorder within a list
        try lib.move(.folder(Sample.selfHosted), to: FolderPath(tab: Sample.home), before: Sample.network)
        XCTAssertEqual(lib.tab(Sample.home)?.folders.map(\.name), ["Self-hosted apps", "Network"])
    }

    func testDirectoryMovesAreRefusedWhenTheyCannotWork() throws {
        var lib = Sample.library()
        // too deep: Self-hosted apps has a sub-directory, so inside Vendors it would reach level 3
        XCTAssertThrowsBM(try lib.move(.folder(Sample.selfHosted), to: FolderPath([Sample.work, Sample.vendors])), containing: "would reach 3 levels deep")
        // into itself or its own sub-directory
        XCTAssertThrowsBM(try lib.move(.folder(Sample.selfHosted), to: FolderPath([Sample.work, Sample.selfHosted, Sample.admin])), containing: "into itself")
        // a tab
        XCTAssertThrowsBM(try lib.move(.folder(Sample.work), to: FolderPath(tab: Sample.home)), containing: "tab can't go inside")
        // a plain directory one level too deep
        XCTAssertThrowsBM(try lib.move(.folder(Sample.vendors), to: FolderPath([Sample.work, Sample.selfHosted, Sample.admin])), containing: "3 levels deep")
        XCTAssertFalse(lib.canMove(.folder(Sample.vendors), to: FolderPath([Sample.work, Sample.selfHosted, Sample.admin])))
        XCTAssertTrue(lib.canMove(.folder(Sample.vendors), to: FolderPath([Sample.work, Sample.selfHosted])))
        XCTAssertEqual(lib, Sample.library(), "a refused move changes nothing")
    }
}

import XCTest
@testable import BookmarkManagerCore

final class SearchTests: XCTestCase {
    func testSearchesNamesAddressesTagsAndDirectoryNamesAcrossTabs() {
        let lib = Sample.library()
        let hits = lib.search("admin")
        XCTAssertEqual(hits.map(\.name), ["Admin pages", "Postgres admin", "Tailscale admin", "UniFi controller"])
        let folder = hits[0]
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.names, ["Work", "Self-hosted apps", "Admin pages"])
        XCTAssertEqual(folder.place, "Work › Self-hosted apps")
        XCTAssertEqual(hits[1].matched, ["name", "tag “admin”"])
        XCTAssertEqual(hits[1].place, "Work › Self-hosted apps › Admin pages")
        XCTAssertEqual(hits[2].matched, ["name", "address"])
        XCTAssertEqual(hits[2].place, "Work")
        XCTAssertEqual(hits[3].matched, ["tag “admin”"])
        XCTAssertEqual(hits[3].tabId, Sample.home)
    }

    func testEveryWordMustMatchAndCaseDoesNotMatter() {
        let lib = Sample.library()
        XCTAssertEqual(lib.search("TAILSCALE ADMIN").map(\.name), ["Tailscale admin"])
        XCTAssertEqual(lib.search("admin network").map(\.name), ["Tailscale admin", "UniFi controller"], "both words, across name / address / tag")
        XCTAssertEqual(lib.search("admin unifi").map(\.name), ["UniFi controller"])
        XCTAssertEqual(lib.search("nothing-like-this").count, 0)
        XCTAssertEqual(lib.search("   ").count, 0)
    }

    func testDescriptionsAreNotSearched() {
        let lib = Sample.library()
        XCTAssertEqual(lib.search("production").count, 0, "Matt: name, address and tags only")
    }
}

import XCTest
@testable import BookmarkManagerCore

final class StoreTests: XCTestCase {
    func testNoFileMeansAFreshLibrary() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        let lib = try store.load()
        XCTAssertEqual(lib.tabs.count, 1)
        XCTAssertFalse(s.exists("library.json"), "nothing is written until something is saved")
    }

    func testSecretsLiveOutsideTheLibraryFile() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        try store.save(Sample.library())
        let text = s.read("library.json")
        XCTAssertTrue(text.contains("Postgres admin"))
        XCTAssertFalse(text.contains("hunter2"), "secrets never go into library.json")
        XCTAssertTrue(s.exists("secrets.enc"))
        XCTAssertTrue(s.exists("secret.key"))
        let perms = try FileManager.default.attributesOfItem(atPath: s.file("secret.key"))[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        let back = try LibraryStore(folder: s.url).load()
        XCTAssertEqual(back, Sample.library(), "a round trip keeps everything, secrets included")
    }

    func testADamagedLibraryFileIsMovedAsideNotLost() throws {
        let s = Scratch()
        try "{ not json".write(toFile: s.file("library.json"), atomically: true, encoding: .utf8)
        let store = LibraryStore(folder: s.url)
        XCTAssertThrowsBM(try store.load(), containing: "could not be read")
        XCTAssertFalse(s.exists("library.json"))
        let aside = try FileManager.default.contentsOfDirectory(atPath: s.path).filter { $0.hasPrefix("library.json.unreadable-") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(s.read(aside[0]), "{ not json")
    }

    func testUnreadableSecretsAreMovedAsideAndReported() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        try store.save(Sample.library())
        try Data([1, 2, 3]).write(to: s.url.appendingPathComponent("secret.key"))
        let again = LibraryStore(folder: s.url)
        let lib = try again.load()
        XCTAssertNotNil(again.problem)
        XCTAssertTrue(again.problem!.contains("type them again"))
        XCTAssertEqual(lib.bookmark(Sample.postgres)?.secret, "", "loaded without the secret")
        XCTAssertTrue(lib.bookmark(Sample.postgres)!.hasSecret, "but still marked as having one")
        XCTAssertFalse(s.exists("secrets.enc")); XCTAssertFalse(s.exists("secret.key"))
    }

    func testAnEmptyTabListIsRepaired() throws {
        let s = Scratch()
        try #"{"app":"Bookmark Manager","library":{"tabs":[],"maxDepth":99}}"#.write(toFile: s.file("library.json"), atomically: true, encoding: .utf8)
        let lib = try LibraryStore(folder: s.url).load()
        XCTAssertEqual(lib.tabs.count, 1)
        XCTAssertEqual(lib.maxDepth, 2)
    }

    func testHomeFollowsTheEnvironment() {
        let s = Scratch()
        setenv("BOOKMARKMANAGER_HOME", s.path, 1)
        defer { unsetenv("BOOKMARKMANAGER_HOME") }
        XCTAssertEqual(Home.folder().standardizedFileURL.path, s.url.standardizedFileURL.path)
    }
}

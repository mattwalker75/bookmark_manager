import Foundation
import XCTest
@testable import BookmarkManagerCore

/// A throwaway folder per test, removed afterwards. Nothing ever touches the real Application Support folder.
final class Scratch {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var path: String { url.path }
    func file(_ name: String) -> String { url.appendingPathComponent(name).path }
    func read(_ name: String) -> String { (try? String(contentsOfFile: file(name), encoding: .utf8)) ?? "" }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name)) }
}

/// A library like the mockups': Work (Self-hosted apps › Admin pages; Vendors; Reading) and Home (Network).
enum Sample {
    static let work = UUID(), selfHosted = UUID(), admin = UUID(), vendors = UUID(), reading = UUID()
    static let home = UUID(), network = UUID()
    static let peopleManager = UUID(), mbm = UUID(), postgres = UUID(), routerStatus = UUID(), webull = UUID(), tailscale = UUID(), unifi = UUID(), hig = UUID()

    /// the default colors with fixed ids, so two sample libraries compare equal
    static let colors: [ColorCode] = ColorCode.defaults()

    static func library() -> Library {
        let colors = Sample.colors
        let important = colors[0].id, workColor = colors[1].id
        let adminFolder = Folder(id: admin, name: "Admin pages", description: "Logins and health pages", bookmarks: [
            Bookmark(id: postgres, name: "Postgres admin", description: "Production database.", url: "https://pg.mini.ts.net:8443/browser/", tags: ["database", "admin"], colorId: important, hasSecret: true, secret: "user: admin\npassword: hunter2\n\ntoken: abc"),
            Bookmark(id: routerStatus, name: "Router status", url: "http://192.168.1.1/status"),
        ])
        let selfHostedFolder = Folder(id: selfHosted, name: "Self-hosted apps", description: "The tools running on the Mac mini", folders: [adminFolder], bookmarks: [
            Bookmark(id: peopleManager, name: "People Manager", description: "A bookmark manager for people.", url: "https://people.mini.ts.net", tags: ["people"], colorId: workColor),
            Bookmark(id: mbm, name: "My Business Manager", url: "http://mbm.mini.ts.net:3030", hasSecret: true, secret: "login: matt\npw: secret"),
        ])
        let vendorsFolder = Folder(id: vendors, name: "Vendors", description: "Accounts we pay for", bookmarks: [
            Bookmark(id: webull, name: "Webull", url: "https://www.webull.com", tags: ["broker"], colorId: important, hasSecret: true, secret: "acct 123"),
        ])
        let readingFolder = Folder(id: reading, name: "Reading", bookmarks: [
            Bookmark(id: hig, name: "HIG", url: "https://developer.apple.com/design/human-interface-guidelines", tags: ["apple", "design"]),
        ])
        let workTab = Folder(id: work, name: "Work", folders: [selfHostedFolder, vendorsFolder, readingFolder], bookmarks: [
            Bookmark(id: tailscale, name: "Tailscale admin", url: "https://login.tailscale.com/admin", tags: ["network"]),
        ])
        let homeTab = Folder(id: home, name: "Home", folders: [
            Folder(id: network, name: "Network", bookmarks: [Bookmark(id: unifi, name: "UniFi controller", url: "https://unifi.local", tags: ["admin", "network"])]),
        ])
        return Library(colors: colors, tabs: [workTab, homeTab])
    }
}

func XCTAssertThrowsBM<T>(_ expr: @autoclosure () throws -> T, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expr(); XCTFail("expected an error containing “\(text)”", file: file, line: line) }
    catch let e as BMError { XCTAssertTrue(e.message.contains(text), "got “\(e.message)”, expected it to contain “\(text)”", file: file, line: line) }
    catch { XCTFail("unexpected error \(error)", file: file, line: line) }
}

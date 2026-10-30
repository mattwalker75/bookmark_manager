import XCTest
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// The app's own logic, each test on its own scratch BOOKMARKMANAGER_HOME (never the real Application Support).
@MainActor
final class AppModelTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }

    override func tearDown() async throws {
        unsetenv("BOOKMARKMANAGER_HOME")
        try? FileManager.default.removeItem(at: home)
    }

    /// A model that never goes on the network for icons.
    private func model() -> AppModel {
        let m = AppModel()
        m.settings.fetchIcons = false
        m.icons.enabled = false
        return m
    }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path) }

    func testStartsWithOneTabSelected() {
        let m = model()
        XCTAssertEqual(m.library.tabs.count, 1)
        XCTAssertEqual(m.selectedTabId, m.library.tabs[0].id)
        XCTAssertEqual(m.selectedPath, FolderPath(tab: m.library.tabs[0].id))
        XCTAssertNil(m.notice)
        XCTAssertFalse(m.isSearching)
    }

    func testChangesAreSavedAndComeBack() throws {
        let m = model()
        m.addTab("Home")
        XCTAssertEqual(m.currentTab?.name, "Home", "a new tab is selected")
        let home = m.selectedTabId
        m.addFolder(name: "Network", description: "Routers", colorId: nil, in: FolderPath(tab: home))
        let net = try XCTUnwrap(m.currentTab?.folders.first)
        m.addBookmark(Bookmark(name: "UniFi", url: "https://unifi.local", hasSecret: true, secret: "pw: x"), in: FolderPath(tab: home).appending(net.id))
        XCTAssertTrue(exists("library.json")); XCTAssertTrue(exists("secrets.enc"))
        XCTAssertNil(m.notice)

        let again = model()
        XCTAssertEqual(again.library.tabs.map(\.name), ["Bookmarks", "Home"])
        XCTAssertEqual(again.library.allBookmarks.first?.secret, "pw: x")
        XCTAssertEqual(again.library.allBookmarks.first?.name, "UniFi")
    }

    func testRefusalsBecomeNoticesAndChangeNothing() {
        let m = model()
        let only = m.library.tabs[0].id
        m.deleteTab(only)
        XCTAssertEqual(m.notice?.title, "The tab wasn't deleted")
        XCTAssertTrue(m.notice!.message.contains("only tab"))
        XCTAssertEqual(m.library.tabs.count, 1)
        m.notice = nil
        m.addBookmark(Bookmark(name: "", url: "x"), in: FolderPath(tab: only))
        XCTAssertEqual(m.notice?.title, "The bookmark wasn't added")
        XCTAssertEqual(m.library.allBookmarks.count, 0)
        XCTAssertFalse(exists("library.json"), "nothing was saved")
    }

    func testSelectionFollowsDeletedDirectories() throws {
        let m = model()
        let tab = m.library.tabs[0].id
        m.addFolder(name: "A", description: "", colorId: nil, in: FolderPath(tab: tab))
        let a = try XCTUnwrap(m.currentTab?.folders.first)
        m.addFolder(name: "B", description: "", colorId: nil, in: FolderPath(tab: tab).appending(a.id))
        let b = try XCTUnwrap(m.library.folder(a.id)?.folders.first)
        let deep = FolderPath([tab, a.id, b.id])
        m.select(deep)
        XCTAssertEqual(m.selectedPath, deep)
        m.deleteFolder(b.id)
        XCTAssertEqual(m.selectedPath, FolderPath([tab, a.id]), "falls back to the parent")
        m.deleteFolder(a.id)
        XCTAssertEqual(m.selectedPath, FolderPath(tab: tab))
    }

    func testDropsMoveThingsAndIgnoreTabTokens() throws {
        let m = model()
        let tab = m.library.tabs[0].id
        m.addFolder(name: "A", description: "", colorId: nil, in: FolderPath(tab: tab))
        let a = try XCTUnwrap(m.currentTab?.folders.first)
        let b = Bookmark(name: "X", url: "https://x.example")
        m.addBookmark(b, in: FolderPath(tab: tab))
        XCTAssertTrue(m.drop(DragItem.bookmark(b.id).token, to: FolderPath([tab, a.id])))
        XCTAssertEqual(m.library.location(ofBookmark: b.id), FolderPath([tab, a.id]))
        XCTAssertFalse(m.drop("tab:\(tab.uuidString)", to: FolderPath([tab, a.id])))
        XCTAssertFalse(m.drop("rubbish", to: FolderPath([tab, a.id])))
        // a directory dropped on its own row is a silent no-op; moved INTO its own sub-directory it is refused with a notice
        XCTAssertFalse(m.drop(DragItem.folder(a.id).token, to: FolderPath([tab, a.id])))
        XCTAssertNil(m.notice)
        m.addFolder(name: "Inside A", description: "", colorId: nil, in: FolderPath([tab, a.id]))
        let inside = try XCTUnwrap(m.library.folder(a.id)?.folders.first)
        XCTAssertFalse(m.drop(DragItem.folder(a.id).token, to: FolderPath([tab, a.id, inside.id])))
        XCTAssertEqual(m.notice?.title, "It wasn't moved")
        XCTAssertTrue(m.canDrop(DragItem.bookmark(b.id).token, to: FolderPath(tab: tab)))
    }

    func testShowInPlaceSelectsAndFlashes() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        m.query = "postgres"
        XCTAssertTrue(m.isSearching)
        let hit = try XCTUnwrap(m.hits.first { $0.name == "Postgres admin" })
        m.showInPlace(hit)
        XCTAssertEqual(m.query, "")
        XCTAssertEqual(m.selectedPath, hit.path)
        XCTAssertEqual(m.selectedTabId, hit.tabId)
        XCTAssertEqual(m.highlightId, hit.id)
        // a directory hit opens the directory holding it
        m.query = "admin pages"
        let dir = try XCTUnwrap(m.hits.first { $0.isFolder })
        m.showInPlace(dir)
        XCTAssertEqual(m.selectedPath, dir.path.parent)
    }

    func testImportReplaceSelectsTheFirstTab() throws {
        let m = model()
        m.addTab("Mine")
        let file = try Transfer.read(try Transfer.export(Sample.library(), includeSecrets: true))
        let notes = m.importFile(file, mode: .replace)
        XCTAssertEqual(notes, [])
        XCTAssertEqual(m.library.tabs.map(\.name), ["Work", "Home", "Dev", "Finance"])
        XCTAssertEqual(m.selectedTabId, m.library.tabs[0].id)
        let again = model()
        XCTAssertEqual(again.library.tabs.count, 4, "saved")
        // add tabs
        let notes2 = again.importFile(file, mode: .addTabs)
        XCTAssertEqual(notes2, ["Added 4 tabs."])
        XCTAssertEqual(again.library.tabs.count, 8)
    }

    func testSettingsPersist() {
        let m = model()
        m.settings.browser = "com.google.Chrome"
        XCTAssertTrue(exists("settings.json"))
        let again = model()
        XCTAssertEqual(again.settings.browser, "com.google.Chrome")
        XCTAssertFalse(again.settings.fetchIcons)
    }

    func testDepthAndColorsLiveInTheLibrary() {
        let m = model()
        m.setMaxDepth(3)
        XCTAssertEqual(model().library.maxDepth, 3)
        m.addColor(name: "Later", rgb: RGB(0.5, 0.2, 0.7))
        XCTAssertEqual(m.library.colors.count, 5)
        let id = m.library.colors[4].id
        m.updateColor(id, name: "Soon")
        XCTAssertEqual(m.library.colors[4].name, "Soon")
        m.removeColor(id)
        XCTAssertEqual(m.library.colors.count, 4)
    }

    func testSampleOnlyWhenAsked() {
        let m = model()
        m.addSampleIfAsked()
        XCTAssertEqual(m.library.allBookmarks.count, 0)
        setenv("BOOKMARKMANAGER_SAMPLE", "1", 1); defer { unsetenv("BOOKMARKMANAGER_SAMPLE") }
        m.addSampleIfAsked()
        XCTAssertGreaterThan(m.library.allBookmarks.count, 10)
        XCTAssertEqual(m.library.tabs.first?.name, "Work")
    }
}

extension AppModel {
    /// Puts a whole library in place (through the normal import path).
    func importFileForTest(_ lib: Library) {
        _ = importFile(ExportFile(secretsIncluded: true, library: lib), mode: .replace)
    }
}

@MainActor
final class QAModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }

    /// A change that can't be saved is put back, so the window never shows something the disk doesn't hold.
    func testAFailedSaveIsPutBack() throws {
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        m.addTab("Mine")
        // another copy writes the file underneath
        var other = try LibraryStore(folder: home).load()
        try other.addTab("Theirs")
        try LibraryStore(folder: home).save(other)
        m.addTab("Lost?")
        XCTAssertEqual(m.notice?.title, "The bookmarks could not be saved")
        XCTAssertTrue(m.notice!.message.contains("another copy of Bookmark Manager"))
        XCTAssertEqual(m.library.tabs.map(\.name), ["Bookmarks", "Mine"], "the refused change is not shown either")
        XCTAssertEqual(m.selectedTabId, m.library.tabs[1].id)
        XCTAssertNotNil(m.reason { try $0.setMaxDepth(0) })
        XCTAssertNil(m.reason { try $0.setMaxDepth(3) })
    }
}

@MainActor
final class AppReviewTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-rev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }

    func testIconFetchAsksForTheSiteRootOnly() {
        XCTAssertEqual(IconFetcher.root(of: URL(string: "http://router.local/admin/reboot?token=SECRET#x")!)?.absoluteString, "http://router.local/")
        XCTAssertEqual(IconFetcher.root(of: URL(string: "https://user:pw@pg.mini.ts.net:8443/browser/")!)?.absoluteString, "https://pg.mini.ts.net:8443/")
    }

    func testEditorReadsDoNotFetchAndFetchesAreQueued() {
        let cache = IconCache(folder: home.appendingPathComponent("icons"))
        cache.enabled = true
        XCTAssertNil(cache.image(for: "https://g", fetch: false)); XCTAssertNil(cache.image(for: "https://github.co", fetch: false))
        XCTAssertEqual(cache.pending, 0, "a half-typed address is never looked up")
        for i in 0..<50 { _ = cache.image(for: "https://host\(i).invalid/") }
        XCTAssertEqual(cache.pending, 50)
        XCTAssertLessThanOrEqual(cache.pending - 46, 4, "at most four in flight")
        cache.enabled = false
        _ = cache.image(for: "https://another.invalid/")
        XCTAssertEqual(cache.pending, 50, "fetching off: nothing new is queued")
    }

    func testDroppingADirectoryOnItselfIsSilent() throws {
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        let tab = m.library.tabs[0].id
        m.addFolder(name: "A", description: "", colorId: nil, in: FolderPath(tab: tab))
        let a = try XCTUnwrap(m.currentTab?.folders.first)
        XCTAssertFalse(m.drop(DragItem.folder(a.id).token, to: FolderPath([tab, a.id])))
        XCTAssertNil(m.notice)
    }

    func testBrowserListLeavesOutTerminals() {
        for b in Browsers.installed() {
            XCTAssertFalse(b.id.contains("iterm"), b.id)
            XCTAssertTrue(Browsers.known.contains(b.id) || Browsers.declares(Bundle(url: b.url)!, scheme: "file"), b.id)
        }
    }
}

/// The tweaks of Oct 29 2026.
@MainActor
final class TweakTests: XCTestCase {
    func testSecretWindowFitsItsTextBetweenTheFloorAndTheCap() {
        let screen = NSSize(width: 1440, height: 900)
        let one = SecretWindows.fittedSize(for: "pin: 1234", screen: screen)
        XCTAssertEqual(one, SecretWindows.floor, "one short line: the floor")
        let nine = SecretWindows.fittedSize(for: (1...9).map { "line \($0): a fairly long line of secret text that is wider than the floor" }.joined(separator: "\n"), screen: screen)
        XCTAssertGreaterThan(nine.width, SecretWindows.floor.width)
        XCTAssertGreaterThan(nine.height, SecretWindows.floor.height)
        XCTAssertLessThan(nine.width, 1440 * 0.6); XCTAssertLessThan(nine.height, 900 * 0.7)
        let forty = SecretWindows.fittedSize(for: Array(repeating: "x", count: 40).joined(separator: "\n"), screen: screen)
        XCTAssertEqual(forty.height, 630, "capped at 70% of the screen's height")
        XCTAssertEqual(forty.width, SecretWindows.floor.width)
        let wide = SecretWindows.fittedSize(for: String(repeating: "w", count: 400), screen: screen)
        XCTAssertEqual(wide.width, 864, "capped at 60% of the screen's width")
        let none = SecretWindows.fittedSize(for: "", screen: screen)
        XCTAssertEqual(none.height, SecretWindows.floor.height, "the 'no secret yet' line is one line tall")
        XCTAssertGreaterThan(none.width, SecretWindows.floor.width, "and wide enough to read in one line")
        // a tiny screen never pushes the cap under the floor
        XCTAssertEqual(SecretWindows.fittedSize(for: forty.debugDescription, screen: NSSize(width: 300, height: 200)), SecretWindows.floor)
    }
}

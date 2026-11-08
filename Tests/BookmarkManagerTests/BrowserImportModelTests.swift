import XCTest
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Import from a browser, the app side (Matt, Nov 8 2026): the new tab is saved and shown; a refusal is a notice.
@MainActor
final class BrowserImportModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-browser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }

    func testTheTabIsSavedAndShown() throws {
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        m.importFileForTest(Sample.library())
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Favorites</H3>
            <DL><p><DT><A HREF="https://www.apple.com/">Apple</A></DL><p>
            <DT><A HREF="https://example.com/">Example</A>
        </DL><p>
        """
        let file = try BrowserBookmarks.parse(Data(html.utf8))
        XCTAssertEqual(file.browser, "Safari")
        let tabsBefore = m.library.tabs.count
        let notes = m.importBrowser(file, tabName: "Safari bookmarks")
        XCTAssertEqual(m.library.tabs.count, tabsBefore + 1)
        XCTAssertEqual(m.library.tabs.last?.name, "Safari bookmarks")
        XCTAssertEqual(m.selectedTabId, m.library.tabs.last?.id, "the new tab is the one shown")
        XCTAssertEqual(notes.first, "Added the tab “Safari bookmarks” with 1 directory and 2 bookmarks.")
        XCTAssertEqual(try LibraryStore(folder: home).load().tabs.last?.bookmarkCount, 2, "on disk")
        XCTAssertNil(m.notice)
        // a blank name: nothing added, a notice
        XCTAssertTrue(m.importBrowser(file, tabName: " ").isEmpty)
        XCTAssertEqual(m.library.tabs.count, tabsBefore + 1); XCTAssertEqual(m.notice?.title, "Nothing was imported")
    }
}

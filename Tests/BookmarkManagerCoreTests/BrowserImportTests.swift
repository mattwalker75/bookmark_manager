import XCTest
@testable import BookmarkManagerCore

/// Import from a browser's bookmarks file (Matt, Nov 8 2026): the HTML every browser exports, read into one new tab.
final class BrowserImportTests: XCTestCase {
    static let chrome = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <!-- This is an automatically generated file.
         It will be read and overwritten.
         DO NOT EDIT! -->
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1700000000" LAST_MODIFIED="1700000001" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
        <DL><p>
            <DT><A HREF="https://a.example/" ADD_DATE="1700000000" ICON="data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==">A &amp; B &#8212; the site</A>
            <DT><H3 ADD_DATE="1700000000">Nested</H3>
            <DL><p>
                <DT><A HREF="https://n.example/x?y=1&amp;z=2">Nested
                    link</A>
                <DT><H3>Deeper</H3>
                <DL><p>
                    <DT><A HREF="https://d.example/">Deep link</A>
                </DL><p>
            </DL><p>
        </DL><p>
        <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
        <DT><A HREF="https://nameless.example/page"></A>
        <DT><H3 ADD_DATE="1700000000">Other bookmarks</H3>
        <DL><p>
        </DL><p>
    </DL><p>
    """
    static let firefox = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks Menu</H1>
    <DL><p>
        <DT><A HREF="https://top.example/">Top level link</A>
        <DT><H3 ADD_DATE="1" LAST_MODIFIED="2" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
        <DD>Add bookmarks to this folder to see them displayed on the Bookmarks Toolbar
        <DL><p>
            <DT><A HREF="https://f.example/" TAGS="photo, work">Firefox link</A>
            <DD>The description of the link
            <DT><A HREF="place:sort=8&amp;maxResults=10">Recent tags</A>
        </DL><p>
        <DT><H3>Mobile Bookmarks</H3>
    </DL>
    """
    static let safari = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <HTML>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <Title>Bookmarks</Title>
    <H1>Bookmarks</H1>
    <DT><H3 FOLDED>Favorites</H3>
    <DL><p>
        <DT><A HREF="https://www.apple.com/">Apple</A>
        <DT><A HREF="mailto:someone@example.com">Mail someone</A>
    </DL><p>
    <DT><H3 FOLDED>Bookmarks Menu</H3>
    <DL><p>
        <DT><A HREF="https://developer.apple.com/">Developer</A>
    </DL><p>
    </HTML>
    """

    func testAChromeFileComesInWithItsFoldersAndTheRestIsCounted() throws {
        let f = try BrowserBookmarks.parse(Data(BrowserImportTests.chrome.utf8))
        XCTAssertEqual(f.browser, "Chrome"); XCTAssertEqual(f.suggestedTabName, "Chrome bookmarks")
        XCTAssertEqual(f.root.folders.map(\.name), ["Bookmarks bar"], "the empty Other bookmarks is left out")
        XCTAssertEqual(f.emptyFolders, 1); XCTAssertEqual(f.skipped, 1, "the bookmarklet")
        XCTAssertEqual(f.root.links.map(\.name), ["nameless.example"], "a link without a name is named after its host")
        let bar = f.root.folders[0]
        XCTAssertEqual(bar.links.map(\.name), ["A & B — the site"], "entities decoded")
        XCTAssertEqual(bar.folders[0].name, "Nested")
        XCTAssertEqual(bar.folders[0].links[0].name, "Nested link", "whitespace inside a name collapsed")
        XCTAssertEqual(bar.folders[0].links[0].url, "https://n.example/x?y=1&z=2")
        XCTAssertEqual(bar.folders[0].folders[0].links[0].name, "Deep link")
        XCTAssertEqual(f.levels, 3); XCTAssertEqual(f.folders, 3); XCTAssertEqual(f.bookmarks, 4)
    }

    func testFirefoxDescriptionsTagsAndSafariFolders() throws {
        let ff = try BrowserBookmarks.parse(Data(BrowserImportTests.firefox.utf8))
        XCTAssertEqual(ff.browser, "Firefox")
        XCTAssertEqual(ff.root.links.map(\.name), ["Top level link"])
        let toolbar = try XCTUnwrap(ff.root.folders.first)
        XCTAssertEqual(toolbar.name, "Bookmarks Toolbar")
        XCTAssertEqual(toolbar.description, "Add bookmarks to this folder to see them displayed on the Bookmarks Toolbar")
        XCTAssertEqual(toolbar.links.count, 1, "the place: pseudo-link is left out"); XCTAssertEqual(ff.skipped, 1)
        XCTAssertEqual(toolbar.links[0].description, "The description of the link"); XCTAssertEqual(toolbar.links[0].tags, ["photo", "work"])
        XCTAssertEqual(ff.emptyFolders, 1, "Mobile Bookmarks had no list at all")
        let sf = try BrowserBookmarks.parse(Data(BrowserImportTests.safari.utf8))
        XCTAssertEqual(sf.browser, "Safari")
        XCTAssertEqual(sf.root.folders.map(\.name), ["Favorites", "Bookmarks Menu"])
        XCTAssertEqual(sf.bookmarks, 3); XCTAssertEqual(sf.root.folders[0].links[1].url, "mailto:someone@example.com")
        // not a bookmarks file at all
        XCTAssertThrowsBM(try BrowserBookmarks.parse(Data("<html><body><p>Hello</p></body></html>".utf8)), containing: "doesn't look like a browser's bookmarks file")
        XCTAssertThrowsBM(try BrowserBookmarks.parse(Data(#"{"app":"Bookmark Manager"}"#.utf8)), containing: "doesn't look like")
        // a Latin-1 file still reads
        let latin = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p><DT><A HREF=\"https://caf.example/\">Caf\u{E9}</A></DL>".data(using: .isoLatin1)!
        XCTAssertEqual(try BrowserBookmarks.parse(latin).root.links[0].name, "Café")
    }

    func testTheFileBecomesOneNewTabAndTheLevelsFollow() throws {
        let f = try BrowserBookmarks.parse(Data(BrowserImportTests.chrome.utf8))
        // the file goes 3 levels deep; a library at 2 is raised to 3 with a note
        let current = Sample.library()
        XCTAssertEqual(current.maxDepth, 2)
        let r = try Transfer.importBrowser(f, tabName: "From Chrome", into: current)
        XCTAssertEqual(r.library.maxDepth, 3)
        XCTAssertEqual(r.library.tabs.map(\.name), ["Work", "Home", "From Chrome"])
        let tab = try XCTUnwrap(r.library.tab(r.tabId))
        XCTAssertEqual(tab.bookmarks.map(\.name), ["nameless.example"])
        XCTAssertEqual(tab.folders[0].folders[0].folders[0].name, "Deeper")
        XCTAssertEqual(tab.bookmarkCount, 4); XCTAssertEqual(tab.allFolders.count, 3)
        XCTAssertEqual(r.notes[0], "Added the tab “From Chrome” with 3 directories and 4 bookmarks.")
        XCTAssertTrue(r.notes.contains { $0.contains("raised to 3") })
        XCTAssertTrue(r.notes.contains { $0.contains("1 item that wasn't a web address") })
        XCTAssertTrue(r.notes.contains { $0.contains("1 empty folder was left out") })
        // what came in is a library like any other: it exports and validates clean, with no repeated ids
        XCTAssertTrue(Transfer.validate(try Transfer.export(r.library, includeSecrets: false)).canImport)
        XCTAssertEqual(Set(r.library.allBookmarks.map(\.id)).count, r.library.allBookmarks.count)
        XCTAssertNil(r.library.allBookmarks.first { $0.hasSecret && $0.id == tab.bookmarks[0].id })
        // a library at 1 level with the levels locked at the top: deeper folders fold into the directory above
        var deep = BrowserBookmarks.Node(name: "Bookmarks")
        var cursor = BrowserBookmarks.Node(name: "L8", links: [BrowserBookmarks.Link(name: "bottom", url: "https://b.example")])
        for i in (1...7).reversed() { cursor = BrowserBookmarks.Node(name: "L\(i)", folders: [cursor], links: [BrowserBookmarks.Link(name: "at \(i)", url: "https://l\(i).example")]) }
        deep.folders = [cursor]
        let deepFile = BrowserBookmarks.File(root: deep, browser: nil, skipped: 0, emptyFolders: 0)
        XCTAssertEqual(deepFile.levels, 8); XCTAssertEqual(deepFile.suggestedTabName, "Imported bookmarks")
        var one = Library.fresh(); one.maxDepth = 1
        let d = try Transfer.importBrowser(deepFile, tabName: "Deep", into: one)
        XCTAssertEqual(d.library.maxDepth, Library.depthRange.upperBound)
        let dtab = try XCTUnwrap(d.library.tab(d.tabId))
        XCTAssertEqual(dtab.bookmarkCount, 8, "every link came in")
        XCTAssertEqual(dtab.levelsBelow, Library.depthRange.upperBound)
        XCTAssertTrue(d.notes.contains { $0.hasPrefix("2 folders deeper than 6 levels were folded") })
        XCTAssertTrue(Transfer.validate(try Transfer.export(d.library, includeSecrets: false)).canImport)
        // a file that fits raises nothing; a blank tab name is refused
        var fits = Library.fresh(); fits.maxDepth = 4
        let ok = try Transfer.importBrowser(f, tabName: "  Mine ", into: fits)
        XCTAssertEqual(ok.library.maxDepth, 4); XCTAssertEqual(ok.library.tabs.last?.name, "Mine"); XCTAssertFalse(ok.notes.contains { $0.contains("raised") })
        XCTAssertThrowsBM(try Transfer.importBrowser(f, tabName: "  ", into: fits), containing: "needs a name")
    }

    /// 1.2.1: a description after a link that was left out (a bookmarklet, say) is dropped, not hung on the kept
    /// link before it; a file of folders alone — an export with no links — reads, and the counts speak.
    func testADescriptionAfterASkippedLinkAndAFoldersOnlyFile() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><A HREF="https://kept.example/">Kept</A>
            <DT><A HREF="javascript:void(0)">Bookmarklet</A>
            <DD>About the bookmarklet
            <DT><A HREF="https://second.example/">Second</A>
            <DD>About the second
            <DT><H3>Folder</H3>
            <DD>About the folder
            <DL><p>
                <DT><A HREF="https://inside.example/">Inside</A>
            </DL><p>
            <DD>A stray description after the list
        </DL><p>
        """
        let f = try BrowserBookmarks.parse(Data(html.utf8))
        XCTAssertEqual(f.root.links.map(\.name), ["Kept", "Second"]); XCTAssertEqual(f.skipped, 1)
        XCTAssertEqual(f.root.links[0].description, "", "the bookmarklet's description does not land on Kept")
        XCTAssertEqual(f.root.links[1].description, "About the second")
        XCTAssertEqual(f.root.folders[0].description, "About the folder")
        XCTAssertEqual(f.root.folders[0].links[0].description, "", "a description after a closed list goes nowhere")
        // folders only: no <A> anywhere, still a bookmarks file
        let foldersOnly = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <DL><p>
            <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
            <DL><p>
                <DT><H3>Work</H3>
                <DL><p></DL><p>
            </DL><p>
            <DT><H3>Other bookmarks</H3>
            <DL><p></DL><p>
        </DL><p>
        """
        let fo = try BrowserBookmarks.parse(Data(foldersOnly.utf8))
        XCTAssertEqual(fo.bookmarks, 0); XCTAssertEqual(fo.folders, 0, "folders with nothing in them are left out")
        XCTAssertEqual(fo.emptyFolders, 3); XCTAssertNil(fo.browser, "the browser is told from the folders that came in, and none did")
        // and a page that merely has a definition list in it is still not one
        XCTAssertThrowsBM(try BrowserBookmarks.parse(Data("<html><body><dl><dt>Term</dt><dd>Meaning</dd></dl></body></html>".utf8)), containing: "doesn't look like")
    }

    func testTheSmallPieces() {
        XCTAssertEqual(BrowserBookmarks.decode("a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#39; &#x263A; &#9731; &unknown; & plain"), "a & b <c> \"d\" 'e' ☺ ☃ &unknown; & plain")
        XCTAssertEqual(BrowserBookmarks.cleanLine("  two\n   words \t here "), "two words here")
        let tokens = BrowserBookmarks.tokens("<!DOCTYPE x><!-- c --><DT><A HREF='https://x' Tags=\"a,b\" ICON=data:x>Name</A>")
        guard case .tag(let name, let closing, let attrs) = tokens[1] else { return XCTFail("expected the A tag") }
        XCTAssertEqual(name, "a"); XCTAssertFalse(closing); XCTAssertEqual(attrs["href"], "https://x"); XCTAssertEqual(attrs["tags"], "a,b"); XCTAssertEqual(attrs["icon"], "data:x")
        guard case .text(let t) = tokens[2] else { return XCTFail("expected text") }
        XCTAssertEqual(t, "Name")
        XCTAssertNil(BrowserBookmarks.browser(of: BrowserBookmarks.Node(name: "x", folders: [BrowserBookmarks.Node(name: "Mine")])))
        XCTAssertEqual(BrowserBookmarks.browser(of: BrowserBookmarks.Node(name: "x", folders: [BrowserBookmarks.Node(name: "Favorites bar")])), "Edge")
    }
}

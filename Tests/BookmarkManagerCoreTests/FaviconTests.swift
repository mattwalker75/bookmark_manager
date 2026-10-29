import XCTest
@testable import BookmarkManagerCore

final class FaviconTests: XCTestCase {
    func testKeyIsTheHost() {
        XCTAssertEqual(Favicons.key(for: URL(string: "https://GitHub.com/matt/repo")!), "github.com")
        XCTAssertEqual(Favicons.key(for: URL(string: "http://mbm.mini.ts.net:3030/x")!), "mbm.mini.ts.net_3030")
        XCTAssertEqual(Favicons.key(for: URL(string: "https://example.com:443/")!), "example.com")
        XCTAssertNil(Favicons.key(for: URL(string: "mailto:a@b.c")!))
    }

    func testCandidatesFromHTMLThenFaviconIco() {
        let page = URL(string: "https://example.com/docs/page.html")!
        let html = """
        <html><head>
        <LINK REL="stylesheet" href="/style.css">
        <link rel='icon' type='image/png' href='/images/icon-32.png'>
        <link rel="shortcut icon" href=favicon2.ico>
        <link rel="apple-touch-icon" sizes="180x180" href="https://cdn.example.com/touch.png">
        <link hreflang="en" rel="alternate" href="/en">
        </head></html>
        """
        let c = Favicons.candidates(page: page, html: html).map(\.absoluteString)
        XCTAssertEqual(c, ["https://cdn.example.com/touch.png", "https://example.com/images/icon-32.png", "https://example.com/docs/favicon2.ico", "https://example.com/favicon.ico"])
    }

    func testNoHTMLMeansJustFaviconIco() {
        let c = Favicons.candidates(page: URL(string: "http://192.168.1.1:8080/status?x=1#top")!, html: nil).map(\.absoluteString)
        XCTAssertEqual(c, ["http://192.168.1.1:8080/favicon.ico"])
    }

    func testAttributeParsing() {
        XCTAssertEqual(Favicons.attribute("rel", in: #"<link data-rel="x" rel="icon" href="a">"#), "icon")
        XCTAssertEqual(Favicons.attribute("href", in: "<link rel=icon href=/a.png>"), "/a.png")
        XCTAssertEqual(Favicons.attribute("href", in: "<link rel=icon href = '/b.png' >"), "/b.png")
        XCTAssertNil(Favicons.attribute("href", in: "<link rel=icon hreflang=en>"))
    }
}

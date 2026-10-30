import XCTest
import Network
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Review 2 (Oct 30 2026), the link checker: the reviewer's cases against a server of our own on 127.0.0.1,
/// asserting the fixed behaviour. Nothing leaves this Mac.
@MainActor
final class NetworkReviewTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-net-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; m.importFileForTest(Sample.library()); return m }
    private func resident() -> Int {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    func testBodiesAreNeverDownloaded() async throws {
        // the reply is built once, before measuring, so the server's own buffer isn't counted against the checker
        let reply = Data("HTTP/1.1 200 OK\r\nContent-Length: 50000000\r\nConnection: close\r\n\r\n".utf8) + Data(repeating: 0x41, count: 50_000_000)
        let server = try SlowHTTP { _, _ in (reply, 0) }
        defer { server.stop() }
        let before = resident()
        let start = Date()
        let v = await LinkChecker.verdict(of: URL(string: "http://127.0.0.1:\(server.port)/huge")!)
        XCTAssertEqual(v, .fine)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertLessThan(resident() - before, 20_000_000, "the 50 MB body was not read into memory")
        // the icon fetcher stops at its own limits too
        let page = Data("HTTP/1.1 200 OK\r\nContent-Length: 10000000\r\nConnection: close\r\n\r\n".utf8) + Data(repeating: 0x20, count: 10_000_000)
        let icons = try SlowHTTP { _, _ in (page, 0) }
        defer { icons.stop() }
        let b2 = resident()
        _ = await IconFetcher.fetch(site: URL(string: "http://127.0.0.1:\(icons.port)/")!)
        XCTAssertLessThan(resident() - b2, 8_000_000, "the root page is read only up to the icon fetcher's cap")
    }

    func testRedirectsGoOnlyWhereABrowserWouldAndNeverDowngrade() async throws {
        let server = try SlowHTTP { _, path in
            switch path {
            case "/to-ftp": return (Data("HTTP/1.1 301 Moved\r\nLocation: ftp://127.0.0.1:1/x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            case "/to-file": return (Data("HTTP/1.1 302 Found\r\nLocation: file:///etc/hosts\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            case "/no-location": return (Data("HTTP/1.1 301 Moved\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            case "/zero": return (Data("HTTP/1.1 000 Nothing\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            case "/loop": return (Data("HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            case "/with-creds": return (Data("HTTP/1.1 301 Moved\r\nLocation: http://user:pw@127.0.0.1:1/x\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            default: return (Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
            }
        }
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        let ftp = await LinkChecker.verdict(of: URL(string: base + "/to-ftp")!); XCTAssertEqual(ftp, .unreachable(LinkVerdict.elsewhere))
        let file = await LinkChecker.verdict(of: URL(string: base + "/to-file")!); XCTAssertEqual(file, .unreachable(LinkVerdict.elsewhere))
        let noLoc = await LinkChecker.verdict(of: URL(string: base + "/no-location")!); XCTAssertEqual(noLoc, .unreachable("Odd answer"))
        let zero = await LinkChecker.verdict(of: URL(string: base + "/zero")!); XCTAssertEqual(zero, .unreachable("Odd answer"))
        let loop = await LinkChecker.verdict(of: URL(string: base + "/loop")!); XCTAssertEqual(loop, .unreachable("Redirects in a circle"))
        // the recorded target never carries a password; the request never did either
        let creds = await LinkChecker.ask(URL(string: base + "/with-creds")!, method: "HEAD")
        XCTAssertEqual(creds.redirectedTo?.contains("user:pw"), false)
        XCTAssertEqual(LinkChecker.bare(URL(string: "https://alice:hunter2@x.example/p?q=1")!).absoluteString, "https://x.example/p?q=1")
        // the downgrade rule, on the delegate itself (a TLS server is more than a test should carry)
        let watcher = LinkChecker.Watcher(originalScheme: "https")
        let task = URLSession.shared.dataTask(with: URL(string: "https://x.example/a")!)
        let response = HTTPURLResponse(url: URL(string: "https://x.example/a")!, statusCode: 301, httpVersion: nil, headerFields: ["Location": "http://x.example/a"])!
        var passed: URLRequest?? = nil
        watcher.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "http://x.example/a")!)) { passed = .some($0) }
        XCTAssertEqual(passed, .some(nil), "https → http is not followed")
        XCTAssertEqual(watcher.downgradeTarget, "http://x.example/a")
        XCTAssertEqual(LinkChecker.Answer(status: 301, redirectedTo: nil, downgradedTo: "http://x.example/a", blocked: false, error: nil).verdict(original: "https://x.example/a"), .downgraded(to: "http://x.example/a"))
        XCTAssertTrue(LinkVerdict.meaningfulMove(from: "https://x.example/a", to: "http://x.example/a"), "scheme counts")
        XCTAssertTrue(LinkVerdict.meaningfulMove(from: "http://x.example:8080/a", to: "http://x.example:9090/a"), "port counts")
        XCTAssertFalse(LinkVerdict.meaningfulMove(from: "http://X.example/a/", to: "http://x.example/a"))
        // the icon fetcher's delegate has the same two rules
        let icons = IconFetcher.AnyCertificate()
        var iconPassed: URLRequest?? = nil
        icons.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "ftp://x.example/a")!)) { iconPassed = .some($0) }
        XCTAssertEqual(iconPassed, .some(nil))
        icons.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "http://x.example/a")!)) { iconPassed = .some($0) }
        XCTAssertEqual(iconPassed, .some(nil), "https → http stopped for icons too")
    }

    func testCredentialsInTheAddressAreNeverSent() async throws {
        let server = try SlowHTTP { raw, _ in
            if raw.contains("Authorization:") { return (Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0) }
            return (Data("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"x\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0)
        }
        defer { server.stop() }
        let v = await LinkChecker.verdict(of: URL(string: "http://alice:hunter2@127.0.0.1:\(server.port)/x")!)
        XCTAssertEqual(v, .refused(code: 401), "a login page is the verdict; the password in the address stays home")
        XCTAssertFalse(server.sawAuthorization)
    }

    func testStoppingKeepsTheLastReportAndNothingAnsweringKeepsItToo() async throws {
        let server = try SlowHTTP { _, path in (Data("HTTP/1.1 \(path == "/gone" ? "404 Not Found" : "200 OK")\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), path.hasPrefix("/slow") ? 3 : 0) }
        defer { server.stop() }
        let m = model()
        var lib = m.library
        for t in lib.tabs.indices { lib.tabs[t].bookmarks = lib.tabs[t].allBookmarks.map { var b = $0; if !b.isSecretOnly { b.url = "http://127.0.0.1:\(server.port)/fine" }; return b }; lib.tabs[t].folders = [] }
        let i = try XCTUnwrap(lib.tabs[0].bookmarks.firstIndex { !$0.isSecretOnly })
        lib.tabs[0].bookmarks[i].url = "http://127.0.0.1:\(server.port)/gone"
        m.importFileForTest(lib)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        let first = try XCTUnwrap(m.linkReport)
        XCTAssertEqual(first.problems.count, 1)
        // a run of slow addresses, stopped at once: the first report stays, a note says so
        var slow = m.library
        for t in slow.tabs.indices { for j in slow.tabs[t].bookmarks.indices where !slow.tabs[t].bookmarks[j].isSecretOnly { slow.tabs[t].bookmarks[j].url = "http://127.0.0.1:\(server.port)/slow\(t)\(j)" } }
        m.importFileForTest(slow)
        m.checkLinks(inMainWindow: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        m.cancelLinkCheck()
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.linkReport?.checkedAt, first.checkedAt, "the old report is still the report")
        XCTAssertFalse(m.linkReport?.problems.contains { $0.verdict == .unreachable(LinkVerdict.cancelled) } ?? true)
        XCTAssertNotNil(m.linkNote)
        // nothing answering at all (closed ports): the old report stays, with a note
        var dead = m.library
        for t in dead.tabs.indices { for j in dead.tabs[t].bookmarks.indices where !dead.tabs[t].bookmarks[j].isSecretOnly { dead.tabs[t].bookmarks[j].url = "http://127.0.0.1:1/" } }
        m.importFileForTest(dead)
        m.checkLinks(automatic: true)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.linkReport?.checkedAt, first.checkedAt)
        XCTAssertTrue(m.linkNote?.contains("Nothing answered") ?? false)
        XCTAssertNil(m.linkBanner, "no banner for a run that told us nothing")
        XCTAssertNotNil(m.settings.lastLinkCheckAt)
    }

    func testUseNewAddressGuards() throws {
        let m = model()
        let b = try XCTUnwrap(m.library.allBookmarks.first { !$0.isSecretOnly })
        // a stale row: the address was edited since the check
        m.linkReport = LinkReport(checkedAt: Date(), checked: 1, problems: [LinkResult(bookmarkId: b.id, url: "http://old.example/", verdict: .moved(to: "http://new.example/"))])
        m.useNewAddress(m.linkReport!.problems[0])
        XCTAssertEqual(m.library.bookmark(b.id)?.url, b.url, "the hand-made address is left alone")
        XCTAssertEqual(m.notice?.title, "The address was changed since")
        XCTAssertEqual(m.linkReport?.problems.count, 1)
        // a target that isn't a web address
        m.notice = nil
        m.linkReport = LinkReport(checkedAt: Date(), checked: 1, problems: [LinkResult(bookmarkId: b.id, url: b.url, verdict: .moved(to: "file:///etc/hosts"))])
        m.useNewAddress(m.linkReport!.problems[0])
        XCTAssertEqual(m.library.bookmark(b.id)?.url, b.url)
        XCTAssertEqual(m.notice?.title, "Not an address for a bookmark")
        XCTAssertEqual(m.linkReport?.problems.count, 1, "the problem stays listed")
        // a good one
        m.linkReport = LinkReport(checkedAt: Date(), checked: 1, problems: [LinkResult(bookmarkId: b.id, url: b.url, verdict: .moved(to: "https://new.example/page"))])
        m.useNewAddress(m.linkReport!.problems[0])
        XCTAssertEqual(m.library.bookmark(b.id)?.url, "https://new.example/page")
        XCTAssertEqual(m.linkReport?.problems.count, 0)
    }

    func testErrorWording() {
        let v = { (e: URLError.Code) in LinkVerdict.from(status: nil, redirectedTo: nil, original: "https://a.example/", error: URLError(e)) }
        XCTAssertEqual(v(.httpTooManyRedirects), .unreachable("Redirects in a circle"))
        XCTAssertEqual(v(.unsupportedURL), .unreachable(LinkVerdict.elsewhere))
        XCTAssertEqual(v(.noPermissionsToReadFile), .unreachable(LinkVerdict.elsewhere))
        XCTAssertEqual(v(.cancelled), .unreachable(LinkVerdict.cancelled))
        XCTAssertEqual(v(.badServerResponse), .unreachable("Odd answer"))
        XCTAssertEqual(LinkVerdict.from(status: 0, redirectedTo: nil, original: "x", error: nil), .unreachable("Odd answer"))
        XCTAssertEqual(LinkVerdict.from(status: 301, redirectedTo: nil, original: "x", error: nil), .unreachable("Odd answer"))
        XCTAssertEqual(LinkVerdict.downgraded(to: "x").group, .quiet)
    }
}

/// A one-request-per-connection HTTP server on 127.0.0.1 whose answers may come late; records whether a request
/// carried an Authorization header. Tests only.
final class SlowHTTP: @unchecked Sendable {
    private let listener: NWListener
    private(set) var port: UInt16 = 0
    private let lock = NSLock()
    private var _auth = false
    var sawAuthorization: Bool { lock.lock(); defer { lock.unlock() }; return _auth }

    init(_ respond: @escaping @Sendable (String, String) -> (Data, TimeInterval)) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] conn in
            let q = DispatchQueue(label: "slowhttp.conn")
            conn.start(queue: q)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if text.contains("Authorization:") { self?.lock.lock(); self?._auth = true; self?.lock.unlock() }
                let parts = text.split(separator: "\r\n").first?.split(separator: " ") ?? []
                let path = parts.count > 1 ? String(parts[1]) : "/"
                let (reply, delay) = respond(text, path)
                q.asyncAfter(deadline: .now() + delay) { conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() }) }
            }
        }
        listener.start(queue: DispatchQueue(label: "slowhttp"))
        guard ready.wait(timeout: .now() + 5) == .success, let p = listener.port?.rawValue else { throw NSError(domain: "SlowHTTP", code: 1) }
        port = p
    }
    func stop() { listener.cancel() }
}

/// Clearing a link mark (Matt, Oct 30 2026): once, or for good.
@MainActor
final class ClearLinkMarkTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-clear-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }

    func testClearOnceAndClearForGood() async throws {
        let server = try SlowHTTP { _, path in (Data("HTTP/1.1 \(path == "/gone" ? "404 Not Found" : "200 OK")\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), 0) }
        defer { server.stop() }
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        var lib = Library.fresh()
        let tab = FolderPath(tab: lib.tabs[0].id)
        let a = Bookmark(name: "Grumpy site", url: "http://127.0.0.1:\(server.port)/gone")
        let b = Bookmark(name: "Fine site", url: "http://127.0.0.1:\(server.port)/fine")
        try lib.addBookmark(a, in: tab); try lib.addBookmark(b, in: tab)
        m.importFileForTest(lib)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.linkProblems.keys.first, a.id)
        // once: the mark goes, the next check brings it back
        m.clearLinkProblem(a.id, forever: false)
        XCTAssertTrue(m.linkProblems.isEmpty)
        XCTAssertTrue(LinkReport.load(from: m.store.folder)?.problems.isEmpty ?? false, "saved")
        XCTAssertFalse(m.library.bookmark(a.id)!.skipLinkCheck)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.linkProblems.keys.first, a.id)
        // for good: the mark goes, the bookmark is left out of the next check, and the editor can turn it back on
        m.clearLinkProblem(a.id, forever: true)
        XCTAssertTrue(m.linkProblems.isEmpty)
        XCTAssertTrue(m.library.bookmark(a.id)!.skipLinkCheck)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(m.linkProblems.isEmpty); XCTAssertEqual(m.linkReport?.checked, 1)
        var back = m.library.bookmark(a.id)!; back.skipLinkCheck = false; m.updateBookmark(back)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(m.linkProblems.keys.first, a.id)
        // the flag travels with an export and reads leniently
        let file = try Transfer.read(try Transfer.export(m.library, includeSecrets: false))
        XCTAssertFalse(file.library.bookmark(a.id)!.skipLinkCheck)
        let old = try JSONDecoder().decode(Bookmark.self, from: Data(#"{"name":"x","url":"https://x.example","skipLinkCheck":"yes"}"#.utf8))
        XCTAssertFalse(old.skipLinkCheck, "a bad value means no")
    }
}

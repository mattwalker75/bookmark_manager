import XCTest
import Network
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// The link check (Matt, Oct 29 2026): verdicts, the report on disk, the marks on rows, and real requests
/// against a tiny server of our own on 127.0.0.1 (nothing leaves this Mac).
@MainActor
final class LinkCheckTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-links-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; m.importFileForTest(Sample.library()); return m }

    func testVerdictsFromStatusRedirectAndError() {
        let v = { (s: Int?, to: String?, e: Error?) in LinkVerdict.from(status: s, redirectedTo: to, original: "https://a.example/x", error: e) }
        XCTAssertEqual(v(200, nil, nil), .fine)
        XCTAssertEqual(v(404, nil, nil), .gone(code: 404)); XCTAssertEqual(v(410, nil, nil), .gone(code: 410))
        XCTAssertEqual(v(401, nil, nil), .refused(code: 401)); XCTAssertEqual(v(403, nil, nil), .refused(code: 403)); XCTAssertEqual(v(429, nil, nil), .refused(code: 429))
        XCTAssertEqual(v(503, nil, nil), .failed(code: 503))
        XCTAssertEqual(v(418, nil, nil), .fine, "an odd 4xx still answered")
        XCTAssertEqual(v(200, "https://b.example/y", nil), .moved(to: "https://b.example/y"))
        XCTAssertEqual(v(200, "https://a.example/x/", nil), .fine, "a trailing slash is not a move")
        XCTAssertEqual(v(404, "https://b.example/y", nil), .gone(code: 404), "moved, but gone where it went")
        XCTAssertEqual(v(nil, nil, URLError(.cannotFindHost)), .unreachable("No such site"))
        XCTAssertEqual(v(nil, nil, URLError(.timedOut)), .unreachable("Timed out"))
        XCTAssertEqual(v(nil, nil, URLError(.cannotConnectToHost)), .unreachable("Nothing answering there"))
        XCTAssertEqual(v(nil, nil, URLError(.serverCertificateUntrusted)), .unreachable("Secure connection failed"))
        XCTAssertFalse(LinkVerdict.meaningfulMove(from: "http://x.example/a", to: "https://x.example/a"), "http → https is not worth a move")
        XCTAssertTrue(LinkVerdict.meaningfulMove(from: "http://x.example/a", to: "https://x.example/b"))
        XCTAssertEqual(LinkVerdict.gone(code: 404).group, .gone); XCTAssertEqual(LinkVerdict.moved(to: "x").group, .moved); XCTAssertEqual(LinkVerdict.failed(code: 500).group, .quiet)
        XCTAssertTrue(LinkVerdict.Group.gone < .moved && LinkVerdict.Group.moved < .quiet)
    }

    func testReportIsKeptOnDiskAndMarksFollowTheAddress() throws {
        let m = model()
        let router = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "Router status" })
        let swift = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "Swift forums" })
        var report = LinkReport(checkedAt: Date(), checked: 10, problems: [LinkResult(bookmarkId: router.id, url: router.url, verdict: .gone(code: 404)), LinkResult(bookmarkId: swift.id, url: swift.url, verdict: .moved(to: "https://forums.swift.org/latest"))], automatic: true)
        m.linkReport = report; report.save(in: m.store.folder)
        XCTAssertEqual(Set(m.linkProblems.keys), [router.id, swift.id])
        XCTAssertNotNil(m.linkBanner)
        // comes back at the next launch
        let again = AppModel(); again.settings.fetchIcons = false; again.icons.enabled = false
        XCTAssertEqual(again.linkReport?.problems, report.problems); XCTAssertEqual(again.linkReport?.checked, 10)
        XCTAssertEqual(again.linkReport?.checkedAt.timeIntervalSince1970 ?? 0, report.checkedAt.timeIntervalSince1970, accuracy: 1, "the date survives to the second")
        // the mark goes as soon as the address is edited
        var fixed = router; fixed.url = "http://192.168.1.1/status2"
        m.updateBookmark(fixed)
        XCTAssertNil(m.linkProblems[router.id]); XCTAssertNotNil(m.linkProblems[swift.id])
        // Use new address takes the move and drops that problem
        m.useNewAddress(report.problems[1])
        XCTAssertEqual(m.library.bookmark(swift.id)?.url, "https://forums.swift.org/latest")
        XCTAssertNil(m.linkProblems[swift.id])
        XCTAssertNil(m.linkBanner, "nothing left to show")
        m.dismissLinkBanner()
        XCTAssertTrue(LinkReport.load(from: m.store.folder)?.bannerDismissed ?? false)
    }

    func testTheScheduleKnowsWhenItIsDue() {
        let m = model()
        XCTAssertFalse(m.linkCheckDue(), "never by default")
        m.settings.linkCheckDays = 7
        XCTAssertTrue(m.linkCheckDue(), "never checked: due")
        m.linkReport = LinkReport(checkedAt: Date().addingTimeInterval(-3 * 86_400), checked: 1, problems: [])
        XCTAssertFalse(m.linkCheckDue())
        XCTAssertTrue(m.linkCheckDue(now: Date().addingTimeInterval(5 * 86_400)))
        m.settings.linkCheckDays = 0
        XCTAssertFalse(m.linkCheckDue(now: Date().addingTimeInterval(400 * 86_400)))
    }

    func testRealRequestsAgainstALocalServer() async throws {
        let server = try TinyHTTP { method, path in
            switch path {
            case "/fine": return "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case "/gone": return "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case "/err": return "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case "/login": return "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case "/nohead": return method == "HEAD" ? "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" : "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
            case "/moved": return "HTTP/1.1 301 Moved Permanently\r\nLocation: /new-home\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case "/new-home": return "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            default: return "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
        }
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        func check(_ path: String) async -> LinkVerdict { await LinkChecker.verdict(of: URL(string: base + path)!) }
        let fine = await check("/fine"); XCTAssertEqual(fine, .fine)
        let gone = await check("/gone"); XCTAssertEqual(gone, .gone(code: 404))
        let err = await check("/err"); XCTAssertEqual(err, .failed(code: 503))
        let login = await check("/login"); XCTAssertEqual(login, .refused(code: 401))
        let nohead = await check("/nohead"); XCTAssertEqual(nohead, .fine, "HEAD refused: GET decides")
        let moved = await check("/moved"); XCTAssertEqual(moved, .moved(to: base + "/new-home"))
        let refused = await LinkChecker.verdict(of: URL(string: "http://127.0.0.1:1/")!)
        XCTAssertEqual(refused, .unreachable("Nothing answering there"))
        // the whole run: progress counts up, only problems are kept
        let ids = (0..<4).map { _ in UUID() }
        var seen: [Int] = []
        let results = await LinkChecker.check([(ids[0], URL(string: base + "/fine")!), (ids[1], URL(string: base + "/gone")!), (ids[2], URL(string: base + "/moved")!), (ids[3], URL(string: base + "/fine")!)]) { seen.append($0) }
        XCTAssertEqual(seen.sorted(), [1, 2, 3, 4])
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.filter(\.verdict.isProblem).map(\.bookmarkId).sorted { $0.uuidString < $1.uuidString }, [ids[1], ids[2]].sorted { $0.uuidString < $1.uuidString })
    }
}

/// A one-request-per-connection HTTP server on 127.0.0.1, for the tests only.
final class TinyHTTP: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16
    private let queue = DispatchQueue(label: "tinyhttp")

    init(_ respond: @escaping @Sendable (String, String) -> String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { conn in
            conn.start(queue: DispatchQueue(label: "tinyhttp.conn"))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let parts = text.split(separator: "\r\n").first?.split(separator: " ") ?? []
                let method = parts.count > 0 ? String(parts[0]) : "GET", path = parts.count > 1 ? String(parts[1]) : "/"
                let reply = respond(method, path)
                conn.send(content: Data(reply.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let p = listener.port?.rawValue else { throw NSError(domain: "TinyHTTP", code: 1) }
        port = p
    }
    func stop() { listener.cancel() }
}

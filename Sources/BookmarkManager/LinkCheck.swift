// Checking addresses (Matt, Oct 29 2026, mockup option B): every bookmark's address, or one directory's, is asked
// for once — HEAD first, GET when the server dislikes HEAD — five at a time, eight seconds each, any certificate
// accepted, nothing kept about the page but the verdict. This is the ONE place the app visits a bookmark's full
// address, and only when asked: by the button, by the directory menu, or by the schedule the person turned on.
// The verdicts are kept in <home>/linkcheck.json so the rows can wear their marks until the next check.
import Foundation
import BookmarkManagerCore

/// What one check found.
enum LinkVerdict: Codable, Equatable {
    case fine
    /// 404 / 410: the page is gone (red)
    case gone(code: Int)
    /// a permanent redirect to another address (blue) — "Use new address" takes it
    case moved(to: String)
    /// 401 / 403 / 429: a login, or robots turned away (amber — may still work in the browser)
    case refused(code: Int)
    /// 5xx: the server is there but broken right now (amber)
    case failed(code: Int)
    /// no such host, timed out, nothing answering (amber)
    case unreachable(String)

    enum Group: Int, Comparable { case gone = 0, moved = 1, quiet = 2; static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue } }

    var isProblem: Bool { self != .fine }
    var group: Group {
        switch self { case .gone: return .gone; case .moved: return .moved; default: return .quiet }
    }
    /// the short verdict on the pill
    var text: String {
        switch self {
        case .fine: return "Fine"
        case .gone(let c): return c == 410 ? "Page gone for good (410)" : "Page gone (404)"
        case .moved: return "Moved for good"
        case .refused(let c): return c == 401 ? "Needs a login (401)" : c == 429 ? "Asked to slow down (429)" : "Refused robots (403)"
        case .failed(let c): return "Server error (\(c))"
        case .unreachable(let why): return why
        }
    }

    /// The verdict from what came back: the final status, the first permanent redirect seen, or the error.
    static func from(status: Int?, redirectedTo: String?, original: String, error: Error?) -> LinkVerdict {
        if let error {
            if let u = error as? URLError {
                switch u.code {
                case .cannotFindHost, .dnsLookupFailed: return .unreachable("No such site")
                case .timedOut: return .unreachable("Timed out")
                case .cannotConnectToHost, .networkConnectionLost: return .unreachable("Nothing answering there")
                case .notConnectedToInternet: return .unreachable("No internet connection")
                case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid: return .unreachable("Secure connection failed")
                default: return .unreachable(u.localizedDescription)
                }
            }
            return .unreachable(error.localizedDescription)
        }
        guard let status else { return .unreachable("No answer") }
        if let to = redirectedTo, meaningfulMove(from: original, to: to), (200..<400).contains(status) { return .moved(to: to) }
        switch status {
        case 200..<400: return .fine
        case 404, 410: return .gone(code: status)
        case 401, 403, 429: return .refused(code: status)
        case 500...: return .failed(code: status)
        default: return .fine   // 4xx we don't understand: the page answered, leave it alone
        }
    }

    /// http→https on the same host, or a trailing slash, is not worth a "moved": only a real new address is.
    static func meaningfulMove(from a: String, to b: String) -> Bool {
        guard let ua = URL(string: a), let ub = URL(string: b) else { return a != b }
        func norm(_ u: URL) -> String { ((u.host ?? "").lowercased()) + (u.path.hasSuffix("/") ? String(u.path.dropLast()) : u.path) + (u.query.map { "?" + $0 } ?? "") }
        return norm(ua) != norm(ub)
    }
}

struct LinkResult: Codable, Equatable, Identifiable {
    var bookmarkId: UUID
    /// the address as it was when checked — a mark applies only while the bookmark still has this address
    var url: String
    var verdict: LinkVerdict
    var id: UUID { bookmarkId }
}

/// One check's outcome: when, how many, the problems (fine ones are not kept), and whether a schedule ran it.
struct LinkReport: Codable, Equatable {
    var checkedAt: Date
    var checked: Int
    var problems: [LinkResult]
    /// "Work › Vendors" when one directory was checked; nil = everything
    var scope: String?
    var automatic = false
    /// the banner for an automatic check was put away
    var bannerDismissed = false
    var seconds: Double = 0

    static func url(in folder: URL) -> URL { folder.appendingPathComponent("linkcheck.json") }
    static func load(from folder: URL) -> LinkReport? {
        guard let d = try? Data(contentsOf: url(in: folder)) else { return nil }
        return try? JSON.decoder.decode(LinkReport.self, from: d)
    }
    func save(in folder: URL) { if let d = try? JSON.encoder.encode(self) { try? d.write(to: LinkReport.url(in: folder), options: .atomic) } }

    var summary: String {
        let n = problems.count
        return n == 0 ? "All \(checked) addresses answered" : "\(n) of \(checked) address\(checked == 1 ? "" : "es") didn't answer as expected"
    }
}

/// How the check is going, for the sheet.
struct LinkCheckProgress: Equatable {
    var done = 0
    var total: Int
}

/// The network part.
enum LinkChecker {
    static let atOnce = 5
    static let timeout: TimeInterval = 8

    /// Checks every pair; `progress` is called on the main actor after each one. Cancel the task to stop early
    /// (what was checked so far comes back).
    static func check(_ items: [(id: UUID, url: URL)], progress: @escaping @MainActor (Int) -> Void) async -> [LinkResult] {
        var results: [LinkResult] = []
        var done = 0
        var index = 0
        await withTaskGroup(of: LinkResult.self) { group in
            func addNext() {
                guard index < items.count else { return }
                let item = items[index]; index += 1
                group.addTask { await LinkResult(bookmarkId: item.id, url: item.url.absoluteString, verdict: verdict(of: item.url)) }
            }
            for _ in 0..<atOnce { addNext() }
            for await r in group {
                results.append(r); done += 1
                let n = done
                await MainActor.run { progress(n) }
                if Task.isCancelled { group.cancelAll(); break }
                addNext()
            }
        }
        return results
    }

    /// One address: HEAD, then GET when the server won't do HEAD.
    static func verdict(of url: URL) async -> LinkVerdict {
        let first = await ask(url, method: "HEAD")
        if let s = first.status, [400, 403, 405, 501].contains(s) {
            return await ask(url, method: "GET").verdict(original: url.absoluteString)
        }
        return first.verdict(original: url.absoluteString)
    }

    struct Answer {
        var status: Int?
        var redirectedTo: String?
        var error: Error?
        func verdict(original: String) -> LinkVerdict { LinkVerdict.from(status: status, redirectedTo: redirectedTo, original: original, error: error) }
    }

    static func ask(_ url: URL, method: String) async -> Answer {
        let delegate = Watcher()
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        c.httpAdditionalHeaders = ["User-Agent": "Bookmark Manager/\(BookmarkManagerCore.version) (Mac; link check)", "Accept": "*/*"]
        let session = URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var r = URLRequest(url: url)
        r.httpMethod = method
        do {
            let (_, response) = try await session.data(for: r)
            return Answer(status: (response as? HTTPURLResponse)?.statusCode, redirectedTo: delegate.permanentTarget, error: nil)
        } catch {
            return Answer(status: nil, redirectedTo: delegate.permanentTarget, error: error)
        }
    }

    /// Accepts any certificate (self-hosted sites), and remembers the first permanent redirect while still following it.
    final class Watcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _target: String?
        var permanentTarget: String? { lock.lock(); defer { lock.unlock() }; return _target }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            if [301, 308].contains(response.statusCode), let to = request.url?.absoluteString {
                lock.lock(); if _target == nil { _target = to }; lock.unlock()
            }
            completionHandler(request)
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: t))
            } else { completionHandler(.performDefaultHandling, nil) }
        }
    }
}

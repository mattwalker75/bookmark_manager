// Checking addresses (Matt, Oct 29 2026, mockup option B): every bookmark's address, or one directory's, is asked
// for once — HEAD first, GET when the server dislikes HEAD — five at a time, eight seconds each, any certificate
// accepted, nothing kept about the page but the verdict. This is the ONE place the app visits a bookmark's full
// address, and only when asked: by the button, by the directory menu, or by the schedule the person turned on.
// The verdicts are kept in <home>/linkcheck.json so the rows can wear their marks until the next check.
//
// Review 2 (Oct 30 2026): only the headers are read, never a body (a 50 MB page cost 50 MB); a redirect is
// followed only to http(s) and never from https down to http; the address's user:password is never sent; a
// cancelled run keeps what it had.
import Foundation
import BookmarkManagerCore

/// What one check found.
enum LinkVerdict: Codable, Equatable {
    case fine
    /// 404 / 410: the page is gone (red)
    case gone(code: Int)
    /// a permanent redirect to another address (blue) — "Use new address" takes it
    case moved(to: String)
    /// the site sends an https address on to plain http: not followed (amber)
    case downgraded(to: String)
    /// 401 / 403 / 429: a login, or robots turned away (amber — may still work in the browser)
    case refused(code: Int)
    /// 5xx: the server is there but broken right now (amber)
    case failed(code: Int)
    /// no such host, timed out, nothing answering, sent somewhere odd (amber)
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
        case .downgraded: return "Sent to an unencrypted address"
        case .refused(let c): return c == 401 ? "Needs a login (401)" : c == 429 ? "Asked to slow down (429)" : "Turned away (403)"
        case .failed(let c): return "Server error (\(c))"
        case .unreachable(let why): return why
        }
    }

    static let elsewhere = "Sent somewhere a browser shouldn't go"
    static let cancelled = "cancelled"

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
                case .httpTooManyRedirects, .redirectToNonExistentLocation: return .unreachable("Redirects in a circle")
                case .unsupportedURL, .badURL, .noPermissionsToReadFile, .fileDoesNotExist, .fileIsDirectory: return .unreachable(elsewhere)
                case .cancelled: return .unreachable(cancelled)
                case .badServerResponse, .cannotParseResponse: return .unreachable("Odd answer")
                default: return .unreachable(u.localizedDescription)
                }
            }
            return .unreachable(error.localizedDescription)
        }
        guard let status, status >= 100 else { return .unreachable("Odd answer") }
        if let to = redirectedTo, meaningfulMove(from: original, to: to), (200..<400).contains(status) { return .moved(to: to) }
        switch status {
        case 200..<300: return .fine
        case 300..<400: return redirectedTo == nil ? .unreachable("Odd answer") : .fine
        case 404, 410: return .gone(code: status)
        case 401, 403, 429: return .refused(code: status)
        case 500...: return .failed(code: status)
        default: return .fine   // 4xx we don't understand: the page answered, leave it alone
        }
    }

    /// A trailing slash, or http stepping up to https, is not worth a "moved"; a new host, path, query, port or a
    /// step down to http is.
    static func meaningfulMove(from a: String, to b: String) -> Bool {
        guard let ua = URL(string: a), let ub = URL(string: b) else { return a != b }
        let upgrade = ua.scheme?.lowercased() == "http" && ub.scheme?.lowercased() == "https"
        func norm(_ u: URL) -> String {
            let scheme = upgrade ? "" : (u.scheme ?? "").lowercased()
            let port = u.port.map { ":\($0)" } ?? ""
            return scheme + "://" + (u.host ?? "").lowercased() + port + (u.path.hasSuffix("/") ? String(u.path.dropLast()) : u.path) + (u.query.map { "?" + $0 } ?? "")
        }
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
    @discardableResult
    func save(in folder: URL) -> Bool {
        guard let d = try? JSON.encoder.encode(self) else { return false }
        return (try? d.write(to: LinkReport.url(in: folder), options: .atomic)) != nil
    }

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

    /// Checks every pair; `progress` is called on the main actor after each one. Cancel the task to stop early:
    /// what was finished comes back, the cancelled ones don't.
    static func check(_ items: [(id: UUID, url: URL)], progress: @escaping @MainActor (Int) -> Void) async -> [LinkResult] {
        var results: [LinkResult] = []
        var done = 0
        var index = 0
        await withTaskGroup(of: LinkResult?.self) { group in
            func addNext() {
                guard index < items.count else { return }
                let item = items[index]; index += 1
                group.addTask {
                    let v = await verdict(of: item.url)
                    if Task.isCancelled || v == .unreachable(LinkVerdict.cancelled) { return nil }
                    return LinkResult(bookmarkId: item.id, url: item.url.absoluteString, verdict: v)
                }
            }
            for _ in 0..<atOnce { addNext() }
            for await r in group {
                if let r { results.append(r) }
                done += 1
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
        var downgradedTo: String?
        var blocked = false
        var error: Error?
        func verdict(original: String) -> LinkVerdict {
            if let to = downgradedTo { return .downgraded(to: to) }
            if blocked { return .unreachable(LinkVerdict.elsewhere) }
            return LinkVerdict.from(status: status, redirectedTo: redirectedTo, original: original, error: error)
        }
    }

    /// The address without its user:password — those are never sent (the site answers 401 and that is the verdict).
    static func bare(_ url: URL) -> URL {
        guard url.user != nil || url.password != nil, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.user = nil; c.password = nil
        return c.url ?? url
    }

    static func ask(_ url: URL, method: String) async -> Answer {
        let url = bare(url)
        let delegate = Watcher(originalScheme: url.scheme?.lowercased() ?? "")
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        c.httpAdditionalHeaders = ["User-Agent": "Bookmark Manager/\(BookmarkManagerCore.version) (Mac; link check)", "Accept": "*/*"]
        let session = URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }   // the headers are all that is wanted; no body is ever read
        var r = URLRequest(url: url)
        r.httpMethod = method
        do {
            let (_, response) = try await session.bytes(for: r)
            return Answer(status: (response as? HTTPURLResponse)?.statusCode, redirectedTo: delegate.permanentTarget, downgradedTo: delegate.downgradeTarget, blocked: delegate.blocked, error: nil)
        } catch {
            return Answer(status: nil, redirectedTo: delegate.permanentTarget, downgradedTo: delegate.downgradeTarget, blocked: delegate.blocked, error: error)
        }
    }

    /// Accepts any certificate (self-hosted sites); remembers the first permanent redirect while still following
    /// it; follows nowhere a browser shouldn't go (only http and https, never https down to http); sends no password.
    final class Watcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let originalScheme: String
        private var _target: String?
        private var _downgrade: String?
        private var _blocked = false
        init(originalScheme: String) { self.originalScheme = originalScheme }
        var permanentTarget: String? { lock.lock(); defer { lock.unlock() }; return _target }
        var downgradeTarget: String? { lock.lock(); defer { lock.unlock() }; return _downgrade }
        var blocked: Bool { lock.lock(); defer { lock.unlock() }; return _blocked }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let to = request.url else { completionHandler(nil); return }
            let scheme = to.scheme?.lowercased() ?? ""
            lock.lock(); defer { lock.unlock() }
            guard scheme == "http" || scheme == "https" else { _blocked = true; completionHandler(nil); return }
            if originalScheme == "https", scheme == "http" { _downgrade = LinkChecker.bare(to).absoluteString; completionHandler(nil); return }
            if [301, 308].contains(response.statusCode), _target == nil { _target = LinkChecker.bare(to).absoluteString }
            var next = request
            next.url = LinkChecker.bare(to)
            completionHandler(next)
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: t))
            } else { completionHandler(.cancelAuthenticationChallenge, nil) }   // a login page is the verdict, never an answer with a password
        }
    }
}

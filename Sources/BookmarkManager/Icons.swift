// Site icons: fetched once per site (the site's front page's own <link rel="icon">, else /favicon.ico), scaled to
// 64 px and kept as PNG in <home>/icons/<host>.png. Only the site's ROOT is ever requested — never a bookmark's
// path or query (a bookmark like http://router/reboot must not be "visited" to find its icon). A site with no
// icon, or one that can't be reached, shows the default link glyph; it is tried again at the next launch, not
// before. A few fetches run at a time; the rest wait. Only when Settings → General allows it.
import AppKit
import BookmarkManagerCore

@MainActor
final class IconCache: ObservableObject {
    /// icons that arrived from the network while the app runs (published: rows showing them redraw)
    @Published private(set) var fetched: [String: NSImage] = [:]
    /// icons read from the icons folder (not published: a view may read them while it is being drawn)
    private var fromDisk: [String: NSImage] = [:]
    var enabled = true
    /// how many fetches may run at once (an import of hundreds of bookmarks must not open hundreds of connections)
    var atOnce = 4
    let folder: URL
    private var failed = Set<String>()
    private var inFlight = Set<String>()
    private var waiting: [(key: String, page: URL)] = []
    private var missingOnDisk = Set<String>()

    init(folder: URL) { self.folder = folder }

    /// The icon for this address, if it is already here; otherwise nil — and, when `fetch` is on, a fetch starts
    /// (the published `fetched` changes when it lands). The editor passes `fetch: false` while an address is being
    /// typed, so half-typed hosts are never looked up.
    func image(for address: String, fetch: Bool = true) -> NSImage? {
        guard let url = Bookmark.link(from: address), let key = Favicons.key(for: url) else { return nil }
        if let i = fetched[key] ?? fromDisk[key] { return i }
        if !missingOnDisk.contains(key) {
            if let i = NSImage(contentsOf: file(key)) { fromDisk[key] = i; return i }
            missingOnDisk.insert(key)
        }
        if fetch && enabled { enqueue(key: key, page: url) }
        return nil
    }

    /// Start fetching an address's icon ahead of time (a bookmark was just added).
    func warm(_ address: String) { _ = image(for: address) }

    /// For the tests: what is in flight or waiting.
    var pending: Int { inFlight.count + waiting.count }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(key + ".png") }

    private func enqueue(key: String, page: URL) {
        guard !failed.contains(key), !inFlight.contains(key), !waiting.contains(where: { $0.key == key }),
              page.scheme == "http" || page.scheme == "https" else { return }
        waiting.append((key, page))
        pump()
    }

    private func pump() {
        while inFlight.count < atOnce, !waiting.isEmpty {
            let next = waiting.removeFirst()
            inFlight.insert(next.key)
            let folder = self.folder
            Task.detached(priority: .utility) { [weak self] in
                let found = await IconFetcher.fetch(site: next.page)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.inFlight.remove(next.key)
                    if let found {
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try? found.png.write(to: folder.appendingPathComponent(next.key + ".png"), options: .atomic)
                        self.fetched[next.key] = found.image
                        self.missingOnDisk.remove(next.key)
                    } else {
                        self.failed.insert(next.key)
                    }
                    self.pump()
                }
            }
        }
    }
}

/// The network part: the site's front page, then each candidate until one decodes as a picture.
enum IconFetcher {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": "Bookmark Manager/\(BookmarkManagerCore.version) (Mac)"]
        // self-hosted sites often have their own certificates: an icon is worth fetching from them too
        return URLSession(configuration: c, delegate: AnyCertificate(), delegateQueue: nil)
    }()

    /// Only the site's root is asked for: scheme://host[:port]/ — the bookmark's own path and query are never sent.
    static func root(of page: URL) -> URL? {
        guard var c = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/"; c.query = nil; c.fragment = nil; c.user = nil; c.password = nil
        return c.url
    }

    static func fetch(site page: URL) async -> (image: NSImage, png: Data)? {
        guard let root = root(of: page) else { return nil }
        var html: String?
        if let (data, response) = try? await session.data(for: request(root, accept: "text/html")),
           (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true, data.count < 2_000_000 {
            html = String(data: data.prefix(300_000), encoding: .utf8) ?? String(decoding: data.prefix(300_000), as: UTF8.self)
        }
        for candidate in Favicons.candidates(page: root, html: html).prefix(5) {
            guard let (data, response) = try? await session.data(for: request(candidate, accept: "image/*")),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  data.count > 0, data.count < 3_000_000,
                  let image = NSImage(data: data), image.size.width > 0, image.size.width <= 4096, image.size.height <= 4096,
                  let png = scaled(image) else { continue }
            return (NSImage(data: png) ?? image, png)
        }
        return nil
    }

    private static func request(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(accept, forHTTPHeaderField: "Accept")
        return r
    }

    /// The picture at 64×64 (its largest representation, for .ico files with several), as PNG.
    static func scaled(_ image: NSImage) -> Data? {
        let side = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let best = image.representations.max { $0.pixelsWide < $1.pixelsWide }
        if let best, let cg = best.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        } else {
            image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Accepts any server certificate (icons only; nothing secret is sent, no cookies, an ephemeral session).
    final class AnyCertificate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: t))
            } else { completionHandler(.performDefaultHandling, nil) }
        }
    }
}

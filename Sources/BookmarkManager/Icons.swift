// Site icons: fetched once per site (the page's own <link rel="icon">, else /favicon.ico), scaled to 64 px and
// kept as PNG in <home>/icons/<host>.png. A site with no icon, or one that can't be reached, shows the default
// link glyph; it is tried again at the next launch, not before. Only when Settings → General allows it.
import AppKit
import BookmarkManagerCore

@MainActor
final class IconCache: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    var enabled = true
    let folder: URL
    private var failed = Set<String>()
    private var inFlight = Set<String>()
    private var missingOnDisk = Set<String>()

    init(folder: URL) { self.folder = folder }

    /// The icon for this address, if it is already here; otherwise nil, and a fetch starts (the published
    /// `images` changes when it lands).
    func image(for address: String) -> NSImage? {
        guard let url = Bookmark.link(from: address), let key = Favicons.key(for: url) else { return nil }
        if let i = images[key] { return i }
        if !missingOnDisk.contains(key) {
            if let i = NSImage(contentsOf: file(key)) { images[key] = i; return i }
            missingOnDisk.insert(key)
        }
        if enabled { fetch(key: key, page: url) }
        return nil
    }

    /// Start fetching an address's icon ahead of time (a bookmark was just added or imported).
    func warm(_ address: String) { _ = image(for: address) }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(key + ".png") }

    private func fetch(key: String, page: URL) {
        guard !failed.contains(key), !inFlight.contains(key), page.scheme == "http" || page.scheme == "https" else { return }
        inFlight.insert(key)
        Task.detached(priority: .utility) { [folder] in
            let found = await IconFetcher.fetch(page: page)
            await MainActor.run {
                self.inFlight.remove(key)
                guard let found else { self.failed.insert(key); return }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? found.png.write(to: folder.appendingPathComponent(key + ".png"), options: .atomic)
                self.images[key] = found.image
                self.missingOnDisk.remove(key)
            }
        }
    }
}

/// The network part: the page's HTML, then each candidate until one decodes as a picture.
enum IconFetcher {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": "Bookmark Manager/\(BookmarkManagerCore.version) (Mac)"]
        // self-hosted sites often have their own certificates: an icon is worth fetching from them too
        return URLSession(configuration: c, delegate: AnyCertificate(), delegateQueue: nil)
    }()

    static func fetch(page: URL) async -> (image: NSImage, png: Data)? {
        var html: String?
        if let (data, response) = try? await session.data(for: request(page, accept: "text/html")),
           (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true, data.count < 2_000_000 {
            html = String(data: data.prefix(300_000), encoding: .utf8) ?? String(decoding: data.prefix(300_000), as: UTF8.self)
        }
        for candidate in Favicons.candidates(page: page, html: html).prefix(5) {
            guard let (data, response) = try? await session.data(for: request(candidate, accept: "image/*")),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  data.count > 0, data.count < 3_000_000,
                  let image = NSImage(data: data), image.size.width > 0, let png = scaled(image) else { continue }
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
        // the biggest representation (an .ico holds several sizes)
        let best = image.representations.max { $0.pixelsWide < $1.pixelsWide }
        if let best, let cg = best.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        } else {
            image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Accepts any server certificate (icons only; nothing secret is sent).
    final class AnyCertificate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let t = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: t))
            } else { completionHandler(.performDefaultHandling, nil) }
        }
    }
}

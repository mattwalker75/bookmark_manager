// Site icons: where a site's icon may be found, from its page's HTML. The app fetches (and keeps) them; this is
// the part with no network in it, so it can be tested.
import Foundation

public enum Favicons {
    /// The name a site's icon is kept under: its host, lowercased ("github.com"). nil for an address without one.
    public static func key(for url: URL) -> String? {
        guard let h = url.host?.lowercased(), !h.isEmpty else { return nil }
        if let p = url.port, p != 80, p != 443 { return "\(h)_\(p)" }
        return h
    }

    /// Where to look for the icon, best first: the page's own <link rel="apple-touch-icon"> and
    /// <link rel="icon"> addresses (as written in `html`, if the page was read), then /favicon.ico at the site's root.
    public static func candidates(page: URL, html: String?) -> [URL] {
        var touch: [URL] = [], icons: [URL] = []
        if let html {
            for tag in linkTags(in: html) {
                guard let rel = attribute("rel", in: tag)?.lowercased(), let href = attribute("href", in: tag), !href.isEmpty,
                      let u = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: page)?.absoluteURL else { continue }
                let rels = rel.split(separator: " ").map(String.init)
                if rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed") { touch.append(u) }
                else if rels.contains("icon") { icons.append(u) }
            }
        }
        var out: [URL] = []
        for u in touch + icons where !out.contains(u) { out.append(u) }
        if var c = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            c.path = "/favicon.ico"; c.query = nil; c.fragment = nil
            if let u = c.url, !out.contains(u) { out.append(u) }
        }
        return out
    }

    /// Every <link …> tag's text.
    static func linkTags(in html: String) -> [String] {
        var out: [String] = []
        let lower = html.lowercased()
        var search = lower.startIndex
        while let r = lower.range(of: "<link", range: search..<lower.endIndex) {
            guard let end = lower.range(of: ">", range: r.upperBound..<lower.endIndex) else { break }
            out.append(String(html[r.lowerBound..<end.upperBound]))
            search = end.upperBound
        }
        return out
    }

    /// The value of an attribute in a tag: name="value", name='value' or name=value.
    static func attribute(_ name: String, in tag: String) -> String? {
        let lower = tag.lowercased()
        var search = lower.startIndex
        while let r = lower.range(of: name, range: search..<lower.endIndex) {
            search = r.upperBound
            // a whole attribute name: not the tail of another ("rel" inside "hreflang"… or "icon" in "data-icon")
            if r.lowerBound > lower.startIndex, let prev = lower[lower.index(before: r.lowerBound)].unicodeScalars.first,
               CharacterSet.alphanumerics.contains(prev) || prev == "-" { continue }
            var i = r.upperBound
            while i < lower.endIndex, lower[i] == " " { i = lower.index(after: i) }
            guard i < lower.endIndex, lower[i] == "=" else { continue }
            i = lower.index(after: i)
            while i < lower.endIndex, lower[i] == " " { i = lower.index(after: i) }
            guard i < lower.endIndex else { return nil }
            let q = tag[i]
            if q == "\"" || q == "'" {
                let start = tag.index(after: i)
                guard let close = tag[start...].firstIndex(of: q) else { return nil }
                return String(tag[start..<close])
            }
            let start = i
            var j = i
            while j < tag.endIndex, !" >".contains(tag[j]) { j = tag.index(after: j) }
            return String(tag[start..<j])
        }
        return nil
    }
}

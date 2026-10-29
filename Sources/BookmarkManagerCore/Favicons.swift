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
                      let u = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: page)?.absoluteURL,
                      u.scheme == "http" || u.scheme == "https" else { continue }   // only addresses that can be fetched (no data: URLs)
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

    /// Every <link …> tag's text. (Searches the text as it is — never through a lowercased copy, whose indices
    /// drift on letters like İ that change length when lowercased; that crashed on a Turkish page in review.)
    static func linkTags(in html: String) -> [String] {
        var out: [String] = []
        var search = html.startIndex
        while let r = html.range(of: "<link", options: .caseInsensitive, range: search..<html.endIndex) {
            guard let end = html.range(of: ">", range: r.upperBound..<html.endIndex) else { break }
            out.append(String(html[r.lowerBound..<end.upperBound]))
            search = end.upperBound
        }
        return out
    }

    /// The value of an attribute in a tag: name="value", name='value' or name=value.
    static func attribute(_ name: String, in tag: String) -> String? {
        var search = tag.startIndex
        while let r = tag.range(of: name, options: .caseInsensitive, range: search..<tag.endIndex) {
            search = r.upperBound
            // a whole attribute name: not the tail of another ("rel" inside "hreflang"… or "icon" in "data-icon")
            if r.lowerBound > tag.startIndex {
                let prev = tag[tag.index(before: r.lowerBound)]
                if prev.isLetter || prev.isNumber || prev == "-" || prev == "_" { continue }
            }
            var i = r.upperBound
            while i < tag.endIndex, tag[i] == " " { i = tag.index(after: i) }
            guard i < tag.endIndex, tag[i] == "=" else { continue }
            i = tag.index(after: i)
            while i < tag.endIndex, tag[i] == " " { i = tag.index(after: i) }
            guard i < tag.endIndex else { return nil }
            let q = tag[i]
            if q == "\"" || q == "'" {
                let start = tag.index(after: i)
                guard let close = tag[start...].firstIndex(of: q) else { return nil }
                return String(tag[start..<close])
            }
            let start = i
            var j = i
            while j < tag.endIndex, !" >".contains(tag[j]) { j = tag.index(after: j) }
            // an unquoted value in a self-closing tag: href=/a.png/> — the "/" before ">" is the tag's, not the value's
            if j < tag.endIndex, tag[j] == ">", j > start, tag[tag.index(before: j)] == "/" { j = tag.index(before: j) }
            return String(tag[start..<j])
        }
        return nil
    }
}

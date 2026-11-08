// Duplicate bookmarks (Matt, Nov 8 2026): bookmarks that point at the same page — the same address letter for
// letter, or one written a little differently (http or https, with or without www, a trailing slash, tracking
// bits after "?", a #fragment). Nothing here deletes anything: the sheet lists each group with where its
// bookmarks live, and the person decides. A group whose every member is marked "meant to be the same"
// (`Bookmark.skipDuplicateCheck` — several Gmail accounts, say) is left out of the sheet from then on.
import Foundation

/// Two or more bookmarks at the same page.
public struct DuplicateGroup: Identifiable, Equatable, Sendable {
    /// the address as compared (host, path, the query that matters)
    public var key: String
    /// the bookmarks, in library order
    public var bookmarkIds: [UUID]
    /// every address is written the same way (after trimming); false = the same page, written differently
    public var exact: Bool
    /// every member is marked as meant to be the same: left out of the sheet unless asked for
    public var allKept: Bool
    public var id: String { key }
    public init(key: String, bookmarkIds: [UUID], exact: Bool, allKept: Bool) { self.key = key; self.bookmarkIds = bookmarkIds; self.exact = exact; self.allKept = allKept }
}

public struct DuplicateReport: Equatable, Sendable {
    /// every group of two or more, the kept ones included
    public var groups: [DuplicateGroup]
    /// how many bookmarks with an address were looked at
    public var checked: Int
    public init(groups: [DuplicateGroup], checked: Int) { self.groups = groups; self.checked = checked }

    /// the groups the sheet lists: at least one member not marked
    public var shown: [DuplicateGroup] { groups.filter { !$0.allKept } }
    /// the groups left out because every member is marked as meant to be the same
    public var keptAway: [DuplicateGroup] { groups.filter(\.allKept) }
    public var shownBookmarks: Int { shown.reduce(0) { $0 + $1.bookmarkIds.count } }
    public var keptAwayBookmarks: Int { keptAway.reduce(0) { $0 + $1.bookmarkIds.count } }

    /// "2 groups of bookmarks point at the same page — 5 bookmarks in all" / "No two bookmarks point at the same page."
    public var summary: String {
        let g = shown.count, b = shownBookmarks
        guard g > 0 else { return "No two bookmarks point at the same page." }
        return "\(g) group\(g == 1 ? "" : "s") of bookmarks point\(g == 1 ? "s" : "") at the same page — \(b) bookmarks in all"
    }
}

extension Library {
    /// Query names that only track where a visitor came from: dropped before addresses are compared.
    static let trackingNames: Set<String> = ["fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "yclid", "twclid", "ttclid",
                                             "_hsenc", "_hsmi", "mkt_tok", "ref_src", "ref_url", "s_kwcid", "oly_anon_id", "oly_enc_id", "vero_id", "wickedid", "_openstat", "spm", "si", "_ga", "_gl"]

    /// The address as duplicates compare it: no scheme (http and https are one page), the host in lower case
    /// without www. or a default port, the path without its trailing slash, the query without tracking names
    /// (sorted, so the order doesn't matter), no fragment. nil = not an address at all (a secret-only item,
    /// "two words"). Other kinds of address (mailto:, tel:) compare as typed, in lower case.
    public static func duplicateKey(_ url: String) -> String? {
        guard let u = Bookmark.link(from: url) else { return nil }
        guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return u.absoluteString.lowercased() }
        guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false), var host = c.host?.lowercased() else { return u.absoluteString.lowercased() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var out = host
        if let p = c.port, !((scheme == "http" && p == 80) || (scheme == "https" && p == 443)) { out += ":\(p)" }
        var path = c.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/" }
        out += path
        c.queryItems = c.queryItems?.filter { !Library.isTracking($0.name) }
        if let items = c.queryItems, !items.isEmpty {
            let sorted = items.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            out += "?" + sorted.map { item in item.value.map { v in "\(item.name)=\(v)" } ?? item.name }.joined(separator: "&")
        }
        return out
    }
    static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("utm_") || trackingNames.contains(n)
    }

    /// Every group of two or more bookmarks at the same page, in the order their first member appears.
    public func findDuplicates() -> DuplicateReport {
        var order: [String] = []
        var members: [String: [Bookmark]] = [:]
        var checked = 0
        for b in allBookmarks {
            guard let key = Library.duplicateKey(b.url) else { continue }
            checked += 1
            if members[key] == nil { order.append(key); members[key] = [] }
            members[key]!.append(b)
        }
        let groups = order.compactMap { key -> DuplicateGroup? in
            let bs = members[key]!
            guard bs.count >= 2 else { return nil }
            let first = bs[0].url.trimmingCharacters(in: .whitespacesAndNewlines)
            return DuplicateGroup(key: key, bookmarkIds: bs.map(\.id), exact: bs.allSatisfy { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == first }, allKept: bs.allSatisfy(\.skipDuplicateCheck))
        }
        return DuplicateReport(groups: groups, checked: checked)
    }

    /// Marks bookmarks as meant to be the same page (or takes the mark off): they stay, and the sheet leaves the
    /// group out while every member is marked. Bookmarks that are gone are skipped.
    public mutating func setKeptAsDuplicates(_ ids: [UUID], _ kept: Bool) {
        for id in ids {
            guard let p = location(ofBookmark: id) else { continue }
            modify(at: p) { f in if let i = f.bookmarks.firstIndex(where: { $0.id == id }) { f.bookmarks[i].skipDuplicateCheck = kept } }
        }
    }
}

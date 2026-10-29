// The search box at the top of the window: every word typed must be found in a bookmark's name, address or
// tags (or a directory's name), in any tab. Each hit says where it lives, so the window can show the path and
// jump there.
import Foundation

public struct SearchHit: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bookmark(Bookmark)
        case folder(Folder)
    }
    public var id: UUID
    public var kind: Kind
    /// the folder holding the bookmark; for a directory hit, the path to the directory itself
    public var path: FolderPath
    /// the names along `path`: the tab first
    public var names: [String]
    /// what matched: "name", "address", "tag “x”"
    public var matched: [String]

    public var tabId: UUID { path.tabId }
    public var name: String { switch kind { case .bookmark(let b): return b.name; case .folder(let f): return f.name } }
    public var isFolder: Bool { if case .folder = kind { return true }; return false }
    /// "Work › Self-hosted apps" — where it is (a directory hit shows the directory that holds it)
    public var place: String {
        if isFolder { return names.dropLast().joined(separator: " › ") }
        return names.joined(separator: " › ")
    }
}

extension Library {
    /// The words of a query, folded (no case, no accents); an empty list means "no search".
    public static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Text as the search compares it: case and accents don't matter ("İstanbul" is found by "istanbul", "café" by "cafe").
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// Every bookmark and directory, in every tab, that matches all the words (names, addresses, tags; directory names).
    public func search(_ query: String) -> [SearchHit] {
        let words = Library.words(query)
        guard !words.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for t in tabs { Library.search(words, in: t, path: FolderPath(tab: t.id), names: [t.name], into: &hits) }
        return hits
    }

    private static func search(_ words: [String], in f: Folder, path: FolderPath, names: [String], into hits: inout [SearchHit]) {
        for sub in f.folders {
            let subPath = path.appending(sub.id), subNames = names + [sub.name]
            let folded = fold(sub.name)
            if words.allSatisfy({ folded.contains($0) }) {
                hits.append(SearchHit(id: sub.id, kind: .folder(sub), path: subPath, names: subNames, matched: ["name"]))
            }
            search(words, in: sub, path: subPath, names: subNames, into: &hits)
        }
        for b in f.bookmarks {
            if let matched = match(words, b) { hits.append(SearchHit(id: b.id, kind: .bookmark(b), path: path, names: names, matched: matched)) }
        }
    }

    /// The fields that matched, or nil when some word matched nothing.
    static func match(_ words: [String], _ b: Bookmark) -> [String]? {
        let name = fold(b.name), url = fold(b.url)
        let tags = b.tags.map { ($0, fold($0)) }
        var fields: [String] = []
        for w in words {
            var found = false
            if name.contains(w) { found = true; if !fields.contains("name") { fields.append("name") } }
            if url.contains(w) { found = true; if !fields.contains("address") { fields.append("address") } }
            for (tag, low) in tags where low.contains(w) {
                found = true
                let label = "tag “\(tag)”"
                if !fields.contains(label) { fields.append(label) }
            }
            if !found { return nil }
        }
        return fields
    }
}

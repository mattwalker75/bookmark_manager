// Import from a browser's bookmarks file (Matt, Nov 8 2026): the HTML file Safari, Chrome, Firefox, Edge and
// Brave all export ("NETSCAPE-Bookmark-file-1": <DL> lists of <DT><H3> folders and <DT><A HREF> links). The
// file's folders become directories inside ONE new tab, its links bookmarks, in the browser's order. Nothing
// here is changed; bookmarklets and other things that aren't addresses are left out and counted.
import Foundation

public enum BrowserBookmarks {
    /// A link as the file has it.
    public struct Link: Equatable, Sendable {
        public var name: String
        public var url: String
        public var description: String
        public var tags: [String]
        public init(name: String, url: String, description: String = "", tags: [String] = []) { self.name = name; self.url = url; self.description = description; self.tags = tags }
    }
    /// A folder as the file has it (the root is the file's top level).
    public struct Node: Equatable, Sendable {
        public var name: String
        public var description: String
        public var folders: [Node]
        public var links: [Link]
        public init(name: String, description: String = "", folders: [Node] = [], links: [Link] = []) { self.name = name; self.description = description; self.folders = folders; self.links = links }
        /// every link in it, at any depth
        public var linkCount: Int { links.count + folders.reduce(0) { $0 + $1.linkCount } }
        public var folderCount: Int { folders.count + folders.reduce(0) { $0 + $1.folderCount } }
        /// how many folder levels are below this one
        public var levels: Int { folders.isEmpty ? 0 : 1 + folders.map(\.levels).max()! }
        /// folders with no link anywhere inside, removed (counted)
        mutating func pruneEmpty(_ dropped: inout Int) {
            for i in folders.indices { folders[i].pruneEmpty(&dropped) }
            let before = folders.count
            folders.removeAll { $0.linkCount == 0 }
            dropped += before - folders.count
        }
    }
    /// What a file holds, ready to be looked at and imported.
    public struct File: Equatable, Sendable {
        public var root: Node
        /// "Safari", "Chrome", "Firefox", "Edge" when the top folders give it away
        public var browser: String?
        /// links that weren't web addresses (bookmarklets, "place:" folders…), left out
        public var skipped: Int
        /// folders with nothing in them, left out
        public var emptyFolders: Int
        public var folders: Int { root.folderCount }
        public var bookmarks: Int { root.linkCount }
        /// how deep the folders go: 0 = links only, 1 = directories, 2 = sub-directories…
        public var levels: Int { root.levels }
        public var suggestedTabName: String { browser.map { "\($0) bookmarks" } ?? "Imported bookmarks" }
    }

    // MARK: parse

    static let howToExport = "Export one from the browser first — Safari: File → Export → Bookmarks…; Chrome: Bookmarks → Bookmark Manager → ⋮ → Export bookmarks; Firefox: Bookmarks → Manage Bookmarks → Import and Backup → Export Bookmarks to HTML…."

    /// The file read; a plain reason when it isn't a browser's bookmarks file.
    public static func parse(_ data: Data) throws -> File {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BMError("That file couldn't be read as text.")
        }
        let lower = text.lowercased()
        // the shape every browser writes: a DL of DTs (links, or folders as H3). A file of folders alone — an export
        // with no links in it — is still that shape; it reads, and the counts say what is in it.
        guard lower.contains("<dl"), lower.contains("<dt"), lower.contains("netscape-bookmark") || lower.contains("<a ") || lower.contains("<h3") else {
            throw BMError("That file doesn't look like a browser's bookmarks file (the HTML one a browser exports). " + howToExport)
        }
        var root = Node(name: "Bookmarks")
        var stack: [Node] = [root]
        var dlPushed: [Bool] = []
        var pendingFolder: Node?
        var skipped = 0
        /// a DD describes the link (or folder) just before it — but only a link that was kept; one after a skipped
        /// link (a bookmarklet, say) must not land on the kept link before that
        var lastLinkKept = false
        enum Capture { case none, h3, a(href: String, tags: [String], description: String), dd }
        var capture = Capture.none
        var buffer = ""
        /// a folder named but never given a list (an empty folder in some exports): it is added where it stood
        func settlePending() {
            if let p = pendingFolder { stack[stack.count - 1].folders.append(p); pendingFolder = nil }
        }
        func applyDD(_ s: String) {
            let d = cleanLine(s)
            guard !d.isEmpty else { return }
            if pendingFolder != nil { pendingFolder!.description = d }
            else if lastLinkKept, !stack[stack.count - 1].links.isEmpty { stack[stack.count - 1].links[stack[stack.count - 1].links.count - 1].description = d }
        }
        for token in tokens(text) {
            switch token {
            case .text(let s):
                switch capture {
                case .none: break
                case .dd:
                    // the description runs until the next tag
                    applyDD(s); capture = .none
                default: buffer += s
                }
            case .tag(let name, let closing, let attrs):
                switch (name, closing) {
                case ("h3", false):
                    settlePending(); lastLinkKept = false; capture = .h3; buffer = ""
                case ("h3", true):
                    let n = cleanLine(buffer)
                    pendingFolder = Node(name: n.isEmpty ? "Untitled folder" : n)
                    capture = .none
                case ("dl", false):
                    lastLinkKept = false
                    if let p = pendingFolder { stack.append(p); pendingFolder = nil; dlPushed.append(true) } else { dlPushed.append(false) }
                case ("dl", true):
                    settlePending(); lastLinkKept = false
                    if dlPushed.popLast() == true, stack.count > 1 {
                        let done = stack.removeLast()
                        stack[stack.count - 1].folders.append(done)
                    }
                case ("a", false):
                    settlePending()
                    let href = attrs["href"] ?? ""
                    let tags = (attrs["tags"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    capture = .a(href: href, tags: tags, description: cleanLine(attrs["description"] ?? "")); buffer = ""
                case ("a", true):
                    if case .a(let href, let tags, let description) = capture {
                        let url = decode(href).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let link = Bookmark.link(from: url), ["http", "https", "ftp", "file", "mailto", "tel"].contains(link.scheme?.lowercased() ?? "") {
                            var n = cleanLine(buffer)
                            if n.isEmpty { n = link.host ?? url }
                            stack[stack.count - 1].links.append(Link(name: n, url: url, description: description, tags: tags))
                            lastLinkKept = true
                        } else { skipped += 1; lastLinkKept = false }
                    }
                    capture = .none
                case ("dd", false):
                    capture = .dd
                case ("dt", false):
                    settlePending()
                    if case .dd = capture { capture = .none }
                default: break
                }
            }
        }
        settlePending()
        // a file that stops short of closing its lists: what was read still counts
        while stack.count > 1 { let done = stack.removeLast(); stack[stack.count - 1].folders.append(done) }
        root = stack[0]
        var empty = 0
        root.pruneEmpty(&empty)
        return File(root: root, browser: browser(of: root), skipped: skipped, emptyFolders: empty)
    }

    /// "Chrome", "Edge", "Firefox" or "Safari" from the names of the top folders; nil when they don't say.
    static func browser(of root: Node) -> String? {
        let names = root.folders.map { $0.name.lowercased() }
        if names.contains(where: { $0.contains("favorites bar") }) { return "Edge" }
        if names.contains(where: { $0.contains("bookmarks bar") }) { return "Chrome" }
        if names.contains(where: { $0.contains("bookmarks toolbar") }) { return "Firefox" }
        if names.contains(where: { $0 == "favorites" || $0 == "favourites" || $0 == "reading list" }) { return "Safari" }
        return nil
    }

    // MARK: the tab

    /// The file as one tab: folders become directories (fresh ids), links bookmarks, in the file's order. A folder
    /// deeper than `maxLevels` is folded into the directory above it (its links land there). Returns how many were.
    public static func makeTab(_ file: File, name: String, maxLevels: Int) -> (tab: Folder, flattened: Int) {
        var flattened = 0
        func fill(_ f: inout Folder, from node: Node, level: Int) {
            f.bookmarks += node.links.map { Bookmark(name: $0.name, description: $0.description, url: $0.url, tags: $0.tags) }
            for sub in node.folders {
                if level + 1 <= maxLevels {
                    var d = Folder(name: sub.name, description: sub.description)
                    fill(&d, from: sub, level: level + 1)
                    f.folders.append(d)
                } else {
                    flattened += 1
                    fill(&f, from: sub, level: level)   // its links and its own folders' links land here
                }
            }
        }
        var tab = Folder(name: name)
        fill(&tab, from: file.root, level: 0)
        return (tab, flattened)
    }

    // MARK: the HTML

    enum Token { case text(String), tag(name: String, closing: Bool, attrs: [String: String]) }

    nonisolated(unsafe) private static let tagPattern = try! NSRegularExpression(pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)((?:\s+[^>]*?)?)\s*/?>|<!--.*?-->|<![^>]*>"#, options: [.dotMatchesLineSeparators])
    nonisolated(unsafe) private static let attrPattern = try! NSRegularExpression(pattern: #"([A-Za-z_:-][A-Za-z0-9_:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)

    /// The file as tags and the text between them (comments and the doctype dropped).
    static func tokens(_ s: String) -> [Token] {
        let ns = s as NSString
        var out: [Token] = []
        var last = 0
        for m in tagPattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out.append(.text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))) }
            last = m.range.location + m.range.length
            guard m.range(at: 2).location != NSNotFound else { continue }   // a comment or the doctype
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            let name = ns.substring(with: m.range(at: 2)).lowercased()
            var attrs: [String: String] = [:]
            if m.range(at: 3).location != NSNotFound {
                let a = ns.substring(with: m.range(at: 3))
                let ans = a as NSString
                for am in attrPattern.matches(in: a, range: NSRange(location: 0, length: ans.length)) {
                    let key = ans.substring(with: am.range(at: 1)).lowercased()
                    let value = [2, 3, 4].compactMap { am.range(at: $0).location == NSNotFound ? nil : ans.substring(with: am.range(at: $0)) }.first ?? ""
                    attrs[key] = value
                }
            }
            out.append(.tag(name: name, closing: closing, attrs: attrs))
        }
        if last < ns.length { out.append(.text(ns.substring(from: last))) }
        return out
    }

    /// A name or description: entities decoded, whitespace collapsed to single spaces, trimmed.
    static func cleanLine(_ s: String) -> String {
        decode(s).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// HTML entities back to text (&amp; &lt; &gt; &quot; &#39; &nbsp; &#NNN; &#xHH;).
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "&", let semi = s[i...].firstIndex(of: ";"), s.distance(from: i, to: semi) <= 10 else { out.append(s[i]); i = s.index(after: i); continue }
            let entity = String(s[s.index(after: i)..<semi])
            var replaced: String?
            switch entity.lowercased() {
            case "amp": replaced = "&"
            case "lt": replaced = "<"
            case "gt": replaced = ">"
            case "quot": replaced = "\""
            case "apos": replaced = "'"
            case "nbsp": replaced = " "
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let v = UInt32(entity.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replaced = String(Character(u)) }
                else if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst(1)), let u = Unicode.Scalar(v) { replaced = String(Character(u)) }
            }
            if let replaced { out += replaced; i = s.index(after: semi) } else { out.append(s[i]); i = s.index(after: i) }
        }
        return out
    }
}

extension Transfer {
    /// A browser's bookmarks file as a NEW tab beside the current ones (Matt, Nov 8 2026). The directory levels
    /// are raised when the file's folders go deeper (up to the most allowed); anything deeper still is folded into
    /// the directory above it. Returns the library, sentences for the user, and the new tab's id.
    public static func importBrowser(_ file: BrowserBookmarks.File, tabName: String, into current: Library) throws -> (library: Library, notes: [String], tabId: UUID) {
        let name = try Library.cleanName(tabName, what: "tab")
        var lib = current
        var notes: [String] = []
        var maxLevels = lib.maxDepth
        if file.levels > maxLevels {
            let raised = min(Library.depthRange.upperBound, file.levels)
            if raised > maxLevels {
                lib.maxDepth = raised; maxLevels = raised
                notes.append("The directory levels were raised to \(raised) to fit the file's folders (Settings → General).")
            }
        }
        let (tab, flattened) = BrowserBookmarks.makeTab(file, name: name, maxLevels: maxLevels)
        lib.tabs.append(tab)
        let d = tab.allFolders.count, b = tab.bookmarkCount
        notes.insert("Added the tab “\(name)” with \(d) director\(d == 1 ? "y" : "ies") and \(b) bookmark\(b == 1 ? "" : "s").", at: 0)
        if flattened > 0 { notes.append("\(flattened) folder\(flattened == 1 ? "" : "s") deeper than \(maxLevels) level\(maxLevels == 1 ? "" : "s") \(flattened == 1 ? "was" : "were") folded into the directory above.") }
        if file.skipped > 0 { notes.append("\(file.skipped) item\(file.skipped == 1 ? " that wasn't" : "s that weren't") a web address (a bookmarklet, say) \(file.skipped == 1 ? "was" : "were") left out.") }
        if file.emptyFolders > 0 { notes.append("\(file.emptyFolders) empty folder\(file.emptyFolders == 1 ? " was" : "s were") left out.") }
        return (lib, notes, tab.id)
    }
}

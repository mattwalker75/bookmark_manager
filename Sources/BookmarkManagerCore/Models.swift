// What Bookmark Manager keeps: a Library of tabs; a tab is a Folder at the top; a folder holds sub-folders
// (directories and sub-directories, as deep as the library's `maxDepth` allows) and bookmarks. Every bookmark has
// a name, an optional description, an address, optional tags (search only), an optional color code and an
// optional multi-line secret (kept encrypted, out of the library file). Folders have an optional description and
// color too. The color codes themselves (a color and what it means) live in the library so an export carries them.
import Foundation

/// The one error type: a plain sentence for the person using the app.
public struct BMError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// A color that can be saved (sRGB 0…1).
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

/// A color and what it means ("red" = "Important"). Bookmarks and folders point at one by id.
public struct ColorCode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rgb: RGB
    public init(id: UUID = UUID(), name: String, rgb: RGB) { self.id = id; self.name = name; self.rgb = rgb }

    /// The most color codes a library may have.
    public static let maximum = 10
    /// The four a new library starts with.
    public static func defaults() -> [ColorCode] {
        [ColorCode(name: "Important", rgb: RGB(0.85, 0.33, 0.31)),
         ColorCode(name: "Work", rgb: RGB(0.18, 0.44, 0.92)),
         ColorCode(name: "Personal", rgb: RGB(0.13, 0.54, 0.28)),
         ColorCode(name: "Reference", rgb: RGB(0.96, 0.62, 0.04))]
    }
}

public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var url: String
    public var tags: [String]
    public var colorId: UUID?
    /// the bookmark has a secret (the text may still be blank after an import without secrets)
    public var hasSecret: Bool
    /// the secret text; kept out of library.json by the store (secrets.enc holds it), in an export only when asked
    public var secret: String
    /// the bundle id of a browser this one opens in instead of the one in Settings; nil = the Settings browser (Matt, Oct 29 2026)
    public var browser: String?

    public init(id: UUID = UUID(), name: String, description: String = "", url: String, tags: [String] = [], colorId: UUID? = nil, hasSecret: Bool = false, secret: String = "", browser: String? = nil) {
        self.id = id; self.name = name; self.description = description; self.url = url; self.tags = tags
        self.colorId = colorId; self.hasSecret = hasSecret; self.secret = secret; self.browser = browser
    }

    enum CodingKeys: String, CodingKey { case id, name, description, url, tags, colorId, hasSecret, secret, browser }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        colorId = try c.decodeIfPresent(UUID.self, forKey: .colorId)
        hasSecret = try c.decodeIfPresent(Bool.self, forKey: .hasSecret) ?? false
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        browser = try c.decodeIfPresent(String.self, forKey: .browser).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A secret-only item: no address at all (a passphrase for a phone, a Wi-Fi password). Its row shows a key
    /// instead of a site icon, the name opens nothing, and its button says Secrets-Only.
    public var isSecretOnly: Bool { url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The tags as typed in the editor: "one, two, three".
    public var tagsText: String { tags.joined(separator: ", ") }
    /// "one, two,three" → ["one", "two", "three"] (trimmed, blanks dropped, repeats dropped).
    public static func parseTags(_ s: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in s.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let v = t.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty, seen.insert(v.lowercased()).inserted { out.append(v) }
        }
        return out
    }

    /// The address as a URL, with https:// put in front when no scheme was typed and spaces written as %20.
    /// nil = can't be opened (or must not be: javascript:, data: and the like are not addresses).
    public var link: URL? { Bookmark.link(from: url) }
    public static func link(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        for bad in ["javascript:", "data:", "vbscript:", "blob:"] where lower.hasPrefix(bad) { return nil }
        if !s.contains("://"), !lower.hasPrefix("mailto:"), !lower.hasPrefix("tel:") {
            guard !s.contains(" ") else { return nil }   // "two words" is not an address; a space INSIDE a real one is encoded below
            s = "https://" + s
        }
        s = s.replacingOccurrences(of: " ", with: "%20")
        guard let u = URL(string: s), let scheme = u.scheme, !scheme.isEmpty else { return nil }
        if scheme == "http" || scheme == "https" { guard let h = u.host, !h.isEmpty else { return nil } }
        return u
    }
}

/// A tab (at the top), a directory, or a sub-directory: the same thing at different depths.
public struct Folder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var colorId: UUID?
    public var folders: [Folder]
    public var bookmarks: [Bookmark]

    public init(id: UUID = UUID(), name: String, description: String = "", colorId: UUID? = nil, folders: [Folder] = [], bookmarks: [Bookmark] = []) {
        self.id = id; self.name = name; self.description = description; self.colorId = colorId; self.folders = folders; self.bookmarks = bookmarks
    }

    enum CodingKeys: String, CodingKey { case id, name, description, colorId, folders, bookmarks }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        colorId = try c.decodeIfPresent(UUID.self, forKey: .colorId)
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        bookmarks = try c.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
    }

    /// Nothing in it at all — the only state a folder or tab can be deleted in.
    public var isEmpty: Bool { folders.isEmpty && bookmarks.isEmpty }
    /// Every bookmark in it, at any depth.
    public var allBookmarks: [Bookmark] { bookmarks + folders.flatMap(\.allBookmarks) }
    /// Every folder in it, at any depth (not itself).
    public var allFolders: [Folder] { folders + folders.flatMap(\.allFolders) }
    /// How many folder levels are below this one: 0 with no sub-folders, 1 with sub-folders that have none, …
    public var levelsBelow: Int { folders.isEmpty ? 0 : 1 + folders.map(\.levelsBelow).max()! }
    public var bookmarkCount: Int { allBookmarks.count }
}

/// Where a folder is: the tab's id, then each folder down to it. `[tab]` is the tab's own top level.
public struct FolderPath: Hashable, Sendable, CustomStringConvertible {
    public var ids: [UUID]
    public init(_ ids: [UUID]) { self.ids = ids }
    public init(tab: UUID) { ids = [tab] }
    public var tabId: UUID { ids[0] }
    public var folderId: UUID { ids[ids.count - 1] }
    /// the tab's top level is depth 0, a directory 1, a sub-directory 2
    public var depth: Int { ids.count - 1 }
    public var isTabRoot: Bool { ids.count == 1 }
    public var parent: FolderPath? { ids.count > 1 ? FolderPath(Array(ids.dropLast())) : nil }
    public func appending(_ id: UUID) -> FolderPath { FolderPath(ids + [id]) }
    public func isInside(_ other: FolderPath) -> Bool { ids.count >= other.ids.count && Array(ids.prefix(other.ids.count)) == other.ids }
    public var description: String { ids.map(\.uuidString).joined(separator: "/") }
}

/// Everything: the tabs, and the color codes they use. There is always at least one tab.
public struct Library: Codable, Equatable, Sendable {
    public var version: Int
    /// how many folder levels a tab may hold: 2 = a directory with a sub-directory in it (Matt's default)
    public var maxDepth: Int
    public var colors: [ColorCode]
    public var tabs: [Folder]

    public static let currentVersion = 1
    public static let depthRange = 1...6

    public init(version: Int = Library.currentVersion, maxDepth: Int = 2, colors: [ColorCode] = ColorCode.defaults(), tabs: [Folder]) {
        self.version = version; self.maxDepth = maxDepth; self.colors = colors; self.tabs = tabs
    }
    /// A new library: one tab, the four default colors.
    public static func fresh() -> Library { Library(tabs: [Folder(name: "Bookmarks")]) }
    /// Nothing of the person's in it yet: one empty tab called Bookmarks, the default colors, the default levels
    /// (a restore over this needs no safety backup; anything else does — review 2).
    public var isFresh: Bool {
        let d = ColorCode.defaults()
        return tabs.count == 1 && tabs[0].isEmpty && tabs[0].name == "Bookmarks" && maxDepth == 2
            && colors.count == d.count && zip(colors, d).allSatisfy { $0.name == $1.name && $0.rgb == $1.rgb }
    }

    enum CodingKeys: String, CodingKey { case version, maxDepth, colors, tabs }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        maxDepth = try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 2
        colors = try c.decodeIfPresent([ColorCode].self, forKey: .colors) ?? ColorCode.defaults()
        tabs = try c.decodeIfPresent([Folder].self, forKey: .tabs) ?? []
    }

    // MARK: finding things

    public func tab(_ id: UUID) -> Folder? { tabs.first { $0.id == id } }
    public func color(_ id: UUID?) -> ColorCode? { id.flatMap { i in colors.first { $0.id == i } } }

    /// The folder at a path (the tab itself for `[tab]`).
    public func folder(at path: FolderPath) -> Folder? {
        guard var f = tab(path.tabId) else { return nil }
        for id in path.ids.dropFirst() {
            guard let next = f.folders.first(where: { $0.id == id }) else { return nil }
            f = next
        }
        return f
    }

    /// Changes the folder at a path in place. False when there is no such folder.
    @discardableResult
    public mutating func modify(at path: FolderPath, _ change: (inout Folder) -> Void) -> Bool {
        guard let ti = tabs.firstIndex(where: { $0.id == path.tabId }) else { return false }
        return Library.modify(&tabs[ti], ids: Array(path.ids.dropFirst()), change)
    }
    private static func modify(_ f: inout Folder, ids: [UUID], _ change: (inout Folder) -> Void) -> Bool {
        guard let first = ids.first else { change(&f); return true }
        guard let i = f.folders.firstIndex(where: { $0.id == first }) else { return false }
        return modify(&f.folders[i], ids: Array(ids.dropFirst()), change)
    }

    /// The path of the folder holding this bookmark.
    public func location(ofBookmark id: UUID) -> FolderPath? {
        for t in tabs { if let p = Library.find(bookmark: id, in: t, path: FolderPath(tab: t.id)) { return p } }
        return nil
    }
    private static func find(bookmark id: UUID, in f: Folder, path: FolderPath) -> FolderPath? {
        if f.bookmarks.contains(where: { $0.id == id }) { return path }
        for sub in f.folders { if let p = find(bookmark: id, in: sub, path: path.appending(sub.id)) { return p } }
        return nil
    }

    /// The path TO this folder (its own id last); a tab's path is `[tab]`.
    public func path(toFolder id: UUID) -> FolderPath? {
        for t in tabs { if let p = Library.find(folder: id, in: t, path: FolderPath(tab: t.id)) { return p } }
        return nil
    }
    private static func find(folder id: UUID, in f: Folder, path: FolderPath) -> FolderPath? {
        if f.id == id { return path }
        for sub in f.folders { if let p = find(folder: id, in: sub, path: path.appending(sub.id)) { return p } }
        return nil
    }

    public func bookmark(_ id: UUID) -> Bookmark? {
        guard let p = location(ofBookmark: id) else { return nil }
        return folder(at: p)?.bookmarks.first { $0.id == id }
    }
    public func folder(_ id: UUID) -> Folder? { path(toFolder: id).flatMap { folder(at: $0) } }

    /// The names along a path: the tab, then each folder. Empty when the path points nowhere.
    public func names(_ path: FolderPath) -> [String] {
        guard var f = tab(path.tabId) else { return [] }
        var out = [f.name]
        for id in path.ids.dropFirst() {
            guard let next = f.folders.first(where: { $0.id == id }) else { return [] }
            out.append(next.name); f = next
        }
        return out
    }

    /// Gives a fresh id to any folder or bookmark whose id is already used (a hand-edited or badly merged file);
    /// two things with one id would otherwise share a secret and be deleted together. Returns how many were changed.
    @discardableResult
    public mutating func repairRepeatedIds() -> Int {
        var seen = Set<UUID>(), fixed = 0
        for t in tabs.indices { Library.repair(&tabs[t], &seen, &fixed) }
        return fixed
    }
    private static func repair(_ f: inout Folder, _ seen: inout Set<UUID>, _ fixed: inout Int) {
        if !seen.insert(f.id).inserted { f.id = UUID(); seen.insert(f.id); fixed += 1 }
        for i in f.bookmarks.indices where !seen.insert(f.bookmarks[i].id).inserted { f.bookmarks[i].id = UUID(); seen.insert(f.bookmarks[i].id); fixed += 1 }
        for i in f.folders.indices { repair(&f.folders[i], &seen, &fixed) }
    }

    public var allBookmarks: [Bookmark] { tabs.flatMap(\.allBookmarks) }
    public var allFolders: [Folder] { tabs.flatMap(\.allFolders) }
    /// The deepest folder level in use anywhere (0 = tabs only hold bookmarks).
    public var deepestLevel: Int { tabs.map(\.levelsBelow).max() ?? 0 }

    // MARK: tabs

    @discardableResult
    public mutating func addTab(_ name: String) throws -> UUID {
        let n = try Library.cleanName(name, what: "tab")
        let t = Folder(name: n)
        tabs.append(t)
        return t.id
    }

    public mutating func renameTab(_ id: UUID, _ name: String) throws {
        let n = try Library.cleanName(name, what: "tab")
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { throw BMError("That tab is gone.") }
        tabs[i].name = n
    }

    /// A tab goes only when it is empty, and never the last one.
    public mutating func deleteTab(_ id: UUID) throws {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { throw BMError("That tab is gone.") }
        guard tabs.count > 1 else { throw BMError("“\(tabs[i].name)” is the only tab. There must always be at least one tab; make another one first.") }
        try Library.checkEmpty(tabs[i], what: "tab")
        tabs.remove(at: i)
    }

    public mutating func moveTab(_ id: UUID, to index: Int) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        let t = tabs.remove(at: i)
        tabs.insert(t, at: max(0, min(index, tabs.count)))
    }

    // MARK: folders

    /// Adds a directory (or sub-directory) inside the folder at `path`, as deep as `maxDepth` allows.
    @discardableResult
    public mutating func addFolder(name: String, description: String = "", colorId: UUID? = nil, in path: FolderPath) throws -> UUID {
        let n = try Library.cleanName(name, what: "directory")
        guard folder(at: path) != nil else { throw BMError("The directory it was going into is gone.") }
        try checkDepth(path.depth + 1, placing: Library.levelName(path.depth + 1))
        let f = Folder(name: n, description: description.trimmingCharacters(in: .whitespacesAndNewlines), colorId: colorId)
        modify(at: path) { $0.folders.append(f) }
        return f.id
    }

    public mutating func updateFolder(_ id: UUID, name: String, description: String, colorId: UUID?) throws {
        let n = try Library.cleanName(name, what: "directory")
        guard let p = path(toFolder: id) else { throw BMError("That directory is gone.") }
        modify(at: p) { $0.name = n; $0.description = description.trimmingCharacters(in: .whitespacesAndNewlines); $0.colorId = colorId }
    }

    /// A directory goes only when it is empty (Matt: so a full one is never deleted by accident).
    public mutating func deleteFolder(_ id: UUID) throws {
        guard let p = path(toFolder: id), let f = folder(at: p) else { throw BMError("That directory is gone.") }
        if p.isTabRoot { try deleteTab(id); return }
        try Library.checkEmpty(f, what: p.depth == 1 ? "directory" : "sub-directory")
        modify(at: p.parent!) { $0.folders.removeAll { $0.id == id } }
    }

    // MARK: bookmarks

    /// Adds a bookmark to the folder at `path` (at the end, or before `before`).
    public mutating func addBookmark(_ b: Bookmark, in path: FolderPath, before: UUID? = nil) throws {
        let clean = try Library.cleaned(b)
        guard folder(at: path) != nil else { throw BMError("The directory it was going into is gone.") }
        guard location(ofBookmark: b.id) == nil else { throw BMError("That bookmark is already in the library.") }
        modify(at: path) { f in
            if let before, let i = f.bookmarks.firstIndex(where: { $0.id == before }) { f.bookmarks.insert(clean, at: i) } else { f.bookmarks.append(clean) }
        }
    }

    /// Saves a changed bookmark where it is.
    public mutating func updateBookmark(_ b: Bookmark) throws {
        let clean = try Library.cleaned(b)
        guard let p = location(ofBookmark: b.id) else { throw BMError("That bookmark is gone.") }
        modify(at: p) { f in if let i = f.bookmarks.firstIndex(where: { $0.id == b.id }) { f.bookmarks[i] = clean } }
    }

    public mutating func deleteBookmark(_ id: UUID) {
        guard let p = location(ofBookmark: id) else { return }
        modify(at: p) { $0.bookmarks.removeAll { $0.id == id } }
    }

    /// Sorts the sub-directories and the bookmarks of one folder by name (once; the order stays manual after).
    public mutating func sortByName(at path: FolderPath) {
        modify(at: path) { f in
            f.folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            f.bookmarks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: color codes

    public func uses(ofColor id: UUID) -> (bookmarks: Int, folders: Int) {
        (allBookmarks.filter { $0.colorId == id }.count, allFolders.filter { $0.colorId == id }.count)
    }

    @discardableResult
    public mutating func addColor(name: String, rgb: RGB) throws -> UUID {
        guard colors.count < ColorCode.maximum else { throw BMError("There can be at most \(ColorCode.maximum) color codes. Remove one to add another.") }
        let c = ColorCode(name: try Library.cleanName(name, what: "color code"), rgb: rgb)
        colors.append(c)
        return c.id
    }

    public mutating func renameColor(_ id: UUID, _ name: String) throws {
        let n = try Library.cleanName(name, what: "color code")
        guard let i = colors.firstIndex(where: { $0.id == id }) else { throw BMError("That color code is gone.") }
        colors[i].name = n
    }

    public mutating func recolor(_ id: UUID, _ rgb: RGB) {
        guard let i = colors.firstIndex(where: { $0.id == id }) else { return }
        colors[i].rgb = rgb
    }

    /// Removes a color code and clears it from every bookmark and folder that used it.
    public mutating func removeColor(_ id: UUID) {
        colors.removeAll { $0.id == id }
        for t in tabs.indices { Library.clearColor(id, in: &tabs[t]) }
    }
    private static func clearColor(_ id: UUID, in f: inout Folder) {
        if f.colorId == id { f.colorId = nil }
        for i in f.bookmarks.indices where f.bookmarks[i].colorId == id { f.bookmarks[i].colorId = nil }
        for i in f.folders.indices { clearColor(id, in: &f.folders[i]) }
    }

    // MARK: depth

    /// Sets how deep directories may go; refused while a deeper directory exists.
    public mutating func setMaxDepth(_ d: Int) throws {
        guard Library.depthRange.contains(d) else { throw BMError("Directory levels must be between \(Library.depthRange.lowerBound) and \(Library.depthRange.upperBound).") }
        let deepest = deepestLevel
        guard deepest <= d else {
            throw BMError("There is a \(Library.levelName(deepest)) \(deepest) levels down, so the levels can't be set to \(d) yet. Move or delete the deeper directories first.")
        }
        maxDepth = d
    }

    func checkDepth(_ level: Int, placing what: String) throws {
        guard level <= maxDepth else {
            throw BMError("A \(what) can't go there: it would be \(level) levels deep and directories may go \(maxDepth) level\(maxDepth == 1 ? "" : "s") deep (Settings → General).")
        }
    }

    // MARK: checks

    /// Blanks and the invisible characters that look like a name but aren't (zero-width space, the Hangul filler…).
    static let blank: CharacterSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{3164}\u{115F}\u{1160}\u{00AD}"))

    static func cleanName(_ name: String, what: String) throws -> String {
        let n = name.trimmingCharacters(in: blank)
        guard !n.isEmpty else { throw BMError("The \(what) needs a name.") }
        return n
    }

    static func cleaned(_ b: Bookmark) throws -> Bookmark {
        var c = b
        c.name = b.name.trimmingCharacters(in: blank)
        c.url = b.url.trimmingCharacters(in: .whitespacesAndNewlines)
        c.description = b.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.name.isEmpty else { throw BMError("The bookmark needs a name.") }
        if c.url.isEmpty {
            // a secret-only item: no address, so it must carry a secret (Matt, Oct 29 2026)
            guard c.hasSecret else { throw BMError("The bookmark needs an address, or a secret if it is a secret-only item.") }
        } else if Bookmark.link(from: c.url) == nil {
            let l = c.url.lowercased()
            if l.hasPrefix("javascript:") || l.hasPrefix("data:") || l.hasPrefix("vbscript:") || l.hasPrefix("blob:") {
                throw BMError("“\(c.url)” isn't an address a browser should open from a bookmark. It should look like https://example.com/page.")
            }
            throw BMError("“\(c.url)” doesn't look like an address that can be opened. It should look like https://example.com/page.")
        }
        if !c.hasSecret { c.secret = "" }
        return c
    }

    static func checkEmpty(_ f: Folder, what: String) throws {
        guard !f.isEmpty else { return }
        let b = f.bookmarkCount, d = f.folders.count
        var parts: [String] = []
        if b > 0 { parts.append("\(b) bookmark\(b == 1 ? "" : "s")") }
        if d > 0 { parts.append("\(d) director\(d == 1 ? "y" : "ies")") }
        throw BMError("“\(f.name)” still has \(parts.joined(separator: " and ")) in it. A \(what) can only be deleted once it is empty — move or delete what is inside first.")
    }

    /// "directory" for level 1, "sub-directory" for 2, "level-3 directory" after that.
    public static func levelName(_ level: Int) -> String {
        switch level { case ...0: return "tab"; case 1: return "directory"; case 2: return "sub-directory"; default: return "level-\(level) directory" }
    }
}

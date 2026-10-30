// Where Bookmark Manager keeps things: ~/Library/Application Support/Bookmark Manager/
//   library.json   every tab, directory and bookmark, and the color codes (secrets left out)
//   secrets.enc    the bookmarks' secrets, encrypted (SecretBox)
//   secret.key     the key that file is encrypted with (readable by you only)
//   settings.json  the app's own settings (the browser, the look)
//   icons/         the site icons it fetched, one per site
// BOOKMARKMANAGER_HOME in the environment points all of it somewhere else (tests, trying things out).
import Foundation

public enum Home {
    public static func folder() -> URL {
        let dir: URL
        if let h = ProcessInfo.processInfo.environment["BOOKMARKMANAGER_HOME"], !h.isEmpty {
            dir = URL(fileURLWithPath: (h as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = base.appendingPathComponent("Bookmark Manager", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

public enum JSON {
    public static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    public static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

public struct LibraryFile: Codable, Equatable, Sendable {
    public var app = "Bookmark Manager"
    public var library: Library
    public init(library: Library) { self.library = library }
}

/// library.json and the secrets that go with it.
public final class LibraryStore: @unchecked Sendable {
    public let folder: URL
    public var url: URL { folder.appendingPathComponent("library.json") }
    public let secrets: SecretBox
    /// a warning from the last load that did not stop it (the secrets could not be read)
    public private(set) var problem: String?
    /// library.json as this store last read or wrote it, so a change made by another copy of the app is noticed
    private var lastSeen: (size: Int, modified: Date)?
    private let lock = NSLock()

    public init(folder: URL = Home.folder()) {
        self.folder = folder
        secrets = SecretBox(folder: folder)
    }

    /// Renames a file to "<name>.unreadable-<date>" beside it; returns the new name.
    @discardableResult
    static func moveAside(_ u: URL) -> String? {
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let name = "\(u.lastPathComponent).unreadable-\(f.string(from: Date()))"
        do { try FileManager.default.moveItem(at: u, to: u.deletingLastPathComponent().appendingPathComponent(name)); return name } catch { return nil }
    }

    /// Loads the library, with every secret in place. No file yet = a fresh library with one tab. A damaged
    /// library.json is moved aside (never overwritten by the next save) and reported; unreadable secrets are moved
    /// aside too and the library loads without them (`problem` says so).
    public func load() throws -> Library {
        problem = nil
        guard FileManager.default.fileExists(atPath: url.path) else { return Library.fresh() }
        var lib: Library
        do { lib = try JSON.decoder.decode(LibraryFile.self, from: Data(contentsOf: url)).library }
        catch {
            let aside = Self.moveAside(url)
            // the secrets go with it: the next save would prune secrets.enc down to the (empty) new library's needs,
            // and the moved-aside library is worthless without them (found in review)
            var kept = "It was kept as \(aside ?? url.lastPathComponent)"
            if let a = aside, let suffix = a.split(separator: ".").last, FileManager.default.fileExists(atPath: secrets.dataURL.path) {
                let copy = "secrets.enc.\(suffix)"
                if (try? FileManager.default.copyItem(at: secrets.dataURL, to: folder.appendingPathComponent(copy))) != nil { kept += " (and its secrets as \(copy))" }
            }
            let reason = error.localizedDescription.hasSuffix(".") ? String(error.localizedDescription.dropLast()) : error.localizedDescription
            throw BMError("The bookmarks file could not be read: \(reason). \(kept) in \(folder.path), so nothing is lost; Bookmark Manager starts with an empty library. Put the files back (renamed to library.json and secrets.enc) once they are fixed, or import an export.")
        }
        if lib.tabs.isEmpty { lib.tabs = [Folder(name: "Bookmarks")] }
        // the levels setting must cover what is there, and stay in range (a hand-edited file may break both)
        if !Library.depthRange.contains(lib.maxDepth) || lib.maxDepth < lib.deepestLevel {
            lib.maxDepth = min(Library.depthRange.upperBound, max(2, lib.deepestLevel))
        }
        lib.repairRepeatedIds()
        var values: [String: String] = [:]
        do { values = try secrets.load() }
        catch {
            let a = Self.moveAside(secrets.dataURL), k = Self.moveAside(secrets.keyURL)
            problem = "\((error as? BMError)?.message ?? error.localizedDescription) The old files were kept as \([a, k].compactMap { $0 }.joined(separator: " and ")). Your bookmarks loaded without their secrets: type them again in each bookmark's editor."
        }
        for t in lib.tabs.indices { LibraryStore.fill(&lib.tabs[t], values) }
        remember()
        return lib
    }

    private func stamp() -> (size: Int, modified: Date)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let size = a[.size] as? Int, let m = a[.modificationDate] as? Date else { return nil }
        return (size, m)
    }
    private func remember() { lock.lock(); lastSeen = stamp(); lock.unlock() }

    /// True when library.json was written by someone else since this store last read or wrote it.
    public var changedOnDisk: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let now = stamp() else { return lastSeen != nil }
        guard let seen = lastSeen else { return true }
        return now.size != seen.size || now.modified != seen.modified
    }
    static func fill(_ f: inout Folder, _ values: [String: String]) {
        for i in f.bookmarks.indices where f.bookmarks[i].hasSecret { f.bookmarks[i].secret = values[f.bookmarks[i].id.uuidString] ?? "" }
        for i in f.folders.indices { fill(&f.folders[i], values) }
    }

    /// Saves the library; the secrets go to the encrypted file, never into library.json.
    public func save(_ lib: Library) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // another copy of Bookmark Manager (or a hand edit) wrote the file since this one read it: writing now would
        // silently throw that away (two copies on one home, found in review)
        if lastSeen != nil, changedOnDisk {
            throw BMError("The bookmarks file was changed by something else — another copy of Bookmark Manager, most likely — since this one read it, so this change was not saved to avoid losing theirs. Quit the other copy, then quit and reopen this one and make the change again.")
        }
        var plain = lib
        var values: [String: String] = [:]
        for t in plain.tabs.indices { LibraryStore.strip(&plain.tabs[t], into: &values) }
        // two steps, so a failure in between loses nothing (review): first the secrets the NEW library needs are added
        // to the ones already there (nothing the on-disk library still points at disappears yet), then library.json,
        // and only once that is in place are secrets that nothing needs any more pruned
        let old = FileManager.default.fileExists(atPath: secrets.dataURL.path) ? ((try? secrets.load()) ?? [:]) : [:]
        try secrets.save(old.merging(values) { _, new in new })
        try JSON.encoder.encode(LibraryFile(library: plain)).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if Set(old.keys) != Set(values.keys) { try secrets.save(values) }
        remember()
    }
    static func strip(_ f: inout Folder, into values: inout [String: String]) {
        for i in f.bookmarks.indices {
            if f.bookmarks[i].hasSecret { values[f.bookmarks[i].id.uuidString] = f.bookmarks[i].secret }
            f.bookmarks[i].secret = ""
        }
        for i in f.folders.indices { strip(&f.folders[i], into: &values) }
    }
}

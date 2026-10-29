// Export, validate and import: the whole library as one .json file — tabs, directories, sub-directories,
// bookmarks, color codes and the directory-levels setting. Secrets go in only when asked (then the file holds
// them in plain text — the window says so). Validate reads a file and lists every problem with where it is,
// without changing anything; Import replaces the library or adds the file's tabs beside yours.
import Foundation

public struct ExportFile: Codable, Equatable, Sendable {
    public var app = "Bookmark Manager"
    public var version = 1
    public var exportedAt = Date()
    public var secretsIncluded: Bool
    public var library: Library
    public init(secretsIncluded: Bool, library: Library) { self.secretsIncluded = secretsIncluded; self.library = library }

    enum CodingKeys: String, CodingKey { case app, version, exportedAt, secretsIncluded, library }
    // lenient on the way in: a hand-edited file missing a date or the flag still reads
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        secretsIncluded = try c.decodeIfPresent(Bool.self, forKey: .secretsIncluded) ?? false
        library = try c.decode(Library.self, forKey: .library)
    }
}

public enum ImportMode: Sendable { case replace, addTabs }

/// One thing wrong (or worth knowing) in a file being validated.
public struct Problem: Equatable, Sendable {
    /// "Work › Vendors › Webull"
    public var place: String
    public var text: String
    /// true = the file can't be imported until this is fixed; false = a note, importing still works
    public var stops: Bool
    public init(place: String, text: String, stops: Bool) { self.place = place; self.text = text; self.stops = stops }
}

public struct ValidationReport: Equatable, Sendable {
    public var problems: [Problem] = []
    public var tabs = 0, folders = 0, bookmarks = 0, withSecrets = 0
    public var secretsIncluded = false
    public var canImport: Bool { !problems.contains { $0.stops } }
    public var stops: [Problem] { problems.filter(\.stops) }
    public var notes: [Problem] { problems.filter { !$0.stops } }

    /// "3 tabs, 7 directories, 41 bookmarks (5 with secrets, included)."
    public var counts: String {
        var s = "\(tabs) tab\(tabs == 1 ? "" : "s"), \(folders) director\(folders == 1 ? "y" : "ies"), \(bookmarks) bookmark\(bookmarks == 1 ? "" : "s")"
        if withSecrets > 0 { s += " (\(withSecrets) with secrets, \(secretsIncluded ? "included" : "left out"))" }
        return s + "."
    }
}

public enum Transfer {
    // MARK: export

    public static func export(_ library: Library, includeSecrets: Bool) throws -> Data {
        var lib = library
        lib.version = Library.currentVersion
        if !includeSecrets { for t in lib.tabs.indices { blankSecrets(&lib.tabs[t]) } }
        return try JSON.encoder.encode(ExportFile(secretsIncluded: includeSecrets, library: lib))
    }
    private static func blankSecrets(_ f: inout Folder) {
        for i in f.bookmarks.indices { f.bookmarks[i].secret = "" }
        for i in f.folders.indices { blankSecrets(&f.folders[i]) }
    }

    // MARK: read and validate

    /// The file as an export; a plain reason when it isn't one.
    public static func read(_ data: Data) throws -> ExportFile {
        guard let f = try? JSON.decoder.decode(ExportFile.self, from: data) else {
            if (try? JSONSerialization.jsonObject(with: data)) == nil { throw BMError("That file isn't JSON (or it is damaged), so it can't be a Bookmark Manager export.") }
            throw BMError("That file isn't a Bookmark Manager export.")
        }
        guard f.app == "Bookmark Manager" else { throw BMError("That file isn't a Bookmark Manager export (it says it is from “\(f.app)”).") }
        guard f.version <= 1 else { throw BMError("That file was made by a newer Bookmark Manager. Update this one first.") }
        return f
    }

    /// Reads a file and lists everything wrong with it, with where each problem is. Changes nothing.
    public static func validate(_ data: Data) -> ValidationReport {
        var r = ValidationReport()
        let f: ExportFile
        do { f = try read(data) } catch { r.problems.append(Problem(place: "The file", text: (error as? BMError)?.message ?? error.localizedDescription, stops: true)); return r }
        r.secretsIncluded = f.secretsIncluded
        let lib = f.library
        r.tabs = lib.tabs.count
        if lib.tabs.isEmpty { r.problems.append(Problem(place: "The file", text: "It has no tabs. A library always has at least one tab.", stops: true)) }
        if !Library.depthRange.contains(lib.maxDepth) {
            r.problems.append(Problem(place: "The file", text: "Directory levels is \(lib.maxDepth); it must be between \(Library.depthRange.lowerBound) and \(Library.depthRange.upperBound).", stops: true))
        }
        if lib.colors.count > ColorCode.maximum {
            r.problems.append(Problem(place: "Color codes", text: "There are \(lib.colors.count) color codes; at most \(ColorCode.maximum) are allowed.", stops: true))
        }
        var colorIds = Set<UUID>()
        for c in lib.colors {
            if c.name.trimmingCharacters(in: .whitespaces).isEmpty { r.problems.append(Problem(place: "Color codes", text: "A color code has no name.", stops: true)) }
            if !colorIds.insert(c.id).inserted { r.problems.append(Problem(place: "Color codes", text: "Two color codes share the same id.", stops: true)) }
            for v in [c.rgb.r, c.rgb.g, c.rgb.b] where !(0...1).contains(v) {
                r.problems.append(Problem(place: "Color code “\(c.name)”", text: "Its color values must be between 0 and 1.", stops: true)); break
            }
        }
        var ids = Set<UUID>()
        var tabNames = Set<String>()
        for t in lib.tabs {
            if !tabNames.insert(t.name.lowercased()).inserted { r.problems.append(Problem(place: t.name, text: "Two tabs have this name. Importing works, but it will be confusing.", stops: false)) }
            check(t, level: 0, place: [], lib: lib, colorIds: colorIds, ids: &ids, report: &r)
        }
        if r.withSecrets > 0 && !f.secretsIncluded {
            r.problems.append(Problem(place: "Secrets", text: "\(r.withSecrets) bookmark\(r.withSecrets == 1 ? " has a secret that is" : "s have secrets that are") not in this file (it was exported without them). After importing, those bookmarks keep the secrets already here, or need them typed again.", stops: false))
        }
        return r
    }

    private static func check(_ f: Folder, level: Int, place: [String], lib: Library, colorIds: Set<UUID>, ids: inout Set<UUID>, report r: inout ValidationReport) {
        let here = place + [f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no name)" : f.name]
        let where_ = here.joined(separator: " › ")
        let what = level == 0 ? "tab" : Library.levelName(level)
        if level > 0 { r.folders += 1 }
        if f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.problems.append(Problem(place: where_, text: "This \(what) has no name.", stops: true)) }
        if !ids.insert(f.id).inserted { r.problems.append(Problem(place: where_, text: "Its id is used twice in the file.", stops: true)) }
        if level > lib.maxDepth { r.problems.append(Problem(place: where_, text: "This \(what) is \(level) levels deep, but the file allows \(lib.maxDepth).", stops: true)) }
        if let c = f.colorId, !colorIds.contains(c) { r.problems.append(Problem(place: where_, text: "Its color code isn't in the file; the color is cleared when importing.", stops: false)) }
        for b in f.bookmarks {
            r.bookmarks += 1
            let bw = (here + [b.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no name)" : b.name]).joined(separator: " › ")
            if b.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.problems.append(Problem(place: bw, text: "This bookmark has no name.", stops: true)) }
            if !ids.insert(b.id).inserted { r.problems.append(Problem(place: bw, text: "Its id is used twice in the file.", stops: true)) }
            if b.url.trimmingCharacters(in: .whitespaces).isEmpty { r.problems.append(Problem(place: bw, text: "This bookmark has no address.", stops: true)) }
            else if Bookmark.link(from: b.url) == nil { r.problems.append(Problem(place: bw, text: "Its address “\(b.url)” can't be opened as it is.", stops: true)) }
            if let c = b.colorId, !colorIds.contains(c) { r.problems.append(Problem(place: bw, text: "Its color code isn't in the file; the color is cleared when importing.", stops: false)) }
            if b.hasSecret {
                r.withSecrets += 1
                if r.secretsIncluded && b.secret.isEmpty { r.problems.append(Problem(place: bw, text: "It is marked as having a secret, but the secret is blank.", stops: false)) }
            } else if !b.secret.isEmpty {
                r.problems.append(Problem(place: bw, text: "It has secret text but isn't marked as having a secret; the text is dropped when importing.", stops: false))
            }
        }
        for sub in f.folders { check(sub, level: level + 1, place: here, lib: lib, colorIds: colorIds, ids: &ids, report: &r) }
    }

    // MARK: import

    /// The library after importing `file` into `current`: `.replace` = the file's library takes over (bookmarks
    /// keep the secrets already here when the file left them out); `.addTabs` = the file's tabs come in beside
    /// the current ones, with fresh ids so nothing collides. Returns notes worth telling the user.
    public static func apply(_ file: ExportFile, to current: Library, mode: ImportMode) -> (library: Library, notes: [String]) {
        var notes: [String] = []
        var lib: Library
        switch mode {
        case .replace:
            lib = file.library
            lib.version = Library.currentVersion
            if !file.secretsIncluded {
                let local = Dictionary(current.allBookmarks.filter(\.hasSecret).map { ($0.id, $0.secret) }, uniquingKeysWith: { a, _ in a })
                var kept = 0, missing = 0
                for t in lib.tabs.indices { restoreSecrets(&lib.tabs[t], local, kept: &kept, missing: &missing) }
                if kept > 0 { notes.append("\(kept) bookmark\(kept == 1 ? "" : "s") kept the secret\(kept == 1 ? "" : "s") already here.") }
                if missing > 0 { notes.append("\(missing) bookmark\(missing == 1 ? " needs its secret" : "s need their secrets") typed again (the file left them out).") }
            }
        case .addTabs:
            lib = current
            // colors: the file's come along when there is room; a color that is already here (same id) is kept as it is
            var dropped = 0
            for c in file.library.colors where !lib.colors.contains(where: { $0.id == c.id }) {
                if lib.colors.count < ColorCode.maximum { lib.colors.append(c) } else { dropped += 1 }
            }
            if dropped > 0 { notes.append("\(dropped) color code\(dropped == 1 ? "" : "s") from the file \(dropped == 1 ? "was" : "were") left out: there is room for \(ColorCode.maximum) at most.") }
            if file.library.deepestLevel > lib.maxDepth {
                lib.maxDepth = min(Library.depthRange.upperBound, file.library.deepestLevel)
                notes.append("Directory levels was raised to \(lib.maxDepth) to fit the file's directories.")
            }
            var blank = 0
            for t in file.library.tabs {
                var copy = freshCopy(t)
                if !file.secretsIncluded { countBlank(copy, &blank) }
                if !file.secretsIncluded { blankAll(&copy) }
                lib.tabs.append(copy)
            }
            if blank > 0 { notes.append("\(blank) bookmark\(blank == 1 ? " needs its secret" : "s need their secrets") typed again (the file left them out).") }
            notes.insert("Added \(file.library.tabs.count) tab\(file.library.tabs.count == 1 ? "" : "s").", at: 0)
        }
        // colors that point nowhere are cleared; secrets on bookmarks not marked as having one are dropped
        let known = Set(lib.colors.map(\.id))
        for t in lib.tabs.indices { tidy(&lib.tabs[t], known) }
        if lib.tabs.isEmpty { lib.tabs = [Folder(name: "Bookmarks")] }
        return (lib, notes)
    }

    private static func restoreSecrets(_ f: inout Folder, _ local: [UUID: String], kept: inout Int, missing: inout Int) {
        for i in f.bookmarks.indices where f.bookmarks[i].hasSecret && f.bookmarks[i].secret.isEmpty {
            if let s = local[f.bookmarks[i].id], !s.isEmpty { f.bookmarks[i].secret = s; kept += 1 } else { missing += 1 }
        }
        for i in f.folders.indices { restoreSecrets(&f.folders[i], local, kept: &kept, missing: &missing) }
    }
    private static func countBlank(_ f: Folder, _ n: inout Int) {
        n += f.bookmarks.filter { $0.hasSecret }.count
        for sub in f.folders { countBlank(sub, &n) }
    }
    private static func blankAll(_ f: inout Folder) {
        for i in f.bookmarks.indices { f.bookmarks[i].secret = "" }
        for i in f.folders.indices { blankAll(&f.folders[i]) }
    }
    private static func tidy(_ f: inout Folder, _ colors: Set<UUID>) {
        if let c = f.colorId, !colors.contains(c) { f.colorId = nil }
        for i in f.bookmarks.indices {
            if let c = f.bookmarks[i].colorId, !colors.contains(c) { f.bookmarks[i].colorId = nil }
            if !f.bookmarks[i].hasSecret { f.bookmarks[i].secret = "" }
        }
        for i in f.folders.indices { tidy(&f.folders[i], colors) }
    }

    /// The same folder with new ids everywhere, so it shares nothing with the original.
    public static func freshCopy(_ f: Folder) -> Folder {
        var c = f
        c.id = UUID()
        c.bookmarks = c.bookmarks.map { var b = $0; b.id = UUID(); return b }
        c.folders = c.folders.map(freshCopy)
        return c
    }
}

// Backups (Matt, Oct 29 2026): one dated file holding everything — the library and the secrets — written on a
// schedule or by hand into a folder, with the oldest falling off the end unless marked as kept. The secrets inside
// are sealed with this Mac's secret key (the same one secrets.enc uses), so a backup is safe to copy anywhere and
// opens on a Mac that has the key file; when a passphrase has been set, the file also carries the key sealed with
// that passphrase, so it opens with the words alone — on a fresh Mac too. The file is plain JSON otherwise.
import Foundation
import CryptoKit
import CommonCrypto

public enum BackupReason: String, Codable, Sendable, Equatable {
    case manual, daily, quit, change, beforeRestore = "before restore"
    public var label: String {
        switch self {
        case .manual: return "by hand"; case .daily: return "daily"; case .quit: return "when the app quit"
        case .change: return "after a change"; case .beforeRestore: return "before a restore"
        }
    }
}

public struct BackupCounts: Codable, Equatable, Sendable {
    public var tabs: Int, directories: Int, bookmarks: Int, secrets: Int
    public init(_ lib: Library) {
        tabs = lib.tabs.count; directories = lib.allFolders.count
        bookmarks = lib.allBookmarks.count; secrets = lib.allBookmarks.filter(\.hasSecret).count
    }
    public var text: String { "\(tabs) tab\(tabs == 1 ? "" : "s") · \(bookmarks) bookmark\(bookmarks == 1 ? "" : "s") · \(secrets) secret\(secrets == 1 ? "" : "s")" }
}

/// This Mac's key, sealed with a key made from a passphrase (PBKDF2-HMAC-SHA256, many rounds), plus the salt.
public struct PassphraseWrap: Codable, Equatable, Sendable {
    public var wrapped: Data
    public var salt: Data
    public var rounds: Int

    public static let defaultRounds = 600_000

    public static func make(key: SymmetricKey, passphrase: String, rounds: Int = defaultRounds) throws -> PassphraseWrap {
        guard passphrase.count >= 8 else { throw BMError("The passphrase needs at least 8 characters.") }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let kek = try derive(passphrase: passphrase, salt: salt, rounds: rounds)
        let raw = key.withUnsafeBytes { Data($0) }
        guard let combined = try AES.GCM.seal(raw, using: kek).combined else { throw BMError("The key could not be sealed.") }
        return PassphraseWrap(wrapped: combined, salt: salt, rounds: rounds)
    }

    public func unwrap(passphrase: String) throws -> SymmetricKey {
        let kek = try PassphraseWrap.derive(passphrase: passphrase, salt: salt, rounds: rounds)
        do {
            let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: wrapped), using: kek)
            guard raw.count == 32 else { throw BMError("The key inside is the wrong size.") }
            return SymmetricKey(data: raw)
        } catch let e as BMError { throw e } catch { throw BMError("That passphrase doesn't open this backup.") }
    }

    static func derive(passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { s -> Int32 in
            pw.withUnsafeBufferPointer { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), UnsafeRawPointer(p.baseAddress!).assumingMemoryBound(to: CChar.self), pw.count,
                                     s.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &out, 32)
            }
        }
        guard status == kCCSuccess else { throw BMError("The passphrase could not be turned into a key.") }
        return SymmetricKey(data: Data(out))
    }
}

/// What a backup file holds.
public struct BackupFile: Codable, Equatable, Sendable {
    public var app = "Bookmark Manager"
    public var kind = "backup"
    public var version = Backup.currentVersion
    public var createdAt: Date
    public var reason: BackupReason
    public var kept = false
    public var note = ""
    public var counts: BackupCounts
    /// every tab, directory and bookmark, secrets blank
    public var library: Library
    /// the secrets ([bookmark id: text] as JSON) sealed with this Mac's key; nil when there are none
    public var secrets: Data?
    /// the key sealed with a passphrase, when one was set
    public var passphrase: PassphraseWrap?
    /// the secrets are written in the clear inside `library` (Matt, Oct 30 2026: a choice in Settings, off by default)
    public var secretsInClear = false

    enum CodingKeys: String, CodingKey { case app, kind, version, createdAt, reason, kept, note, counts, library, secrets, passphrase, secretsInClear }
    public init(createdAt: Date, reason: BackupReason, counts: BackupCounts, library: Library) {
        self.createdAt = createdAt; self.reason = reason; self.counts = counts; self.library = library
    }
    // lenient, like every other file: a backup from a slightly different version still reads where it can
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date.distantPast
        reason = (try? c.decodeIfPresent(BackupReason.self, forKey: .reason)) ?? .manual
        kept = try c.decodeIfPresent(Bool.self, forKey: .kept) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        library = try c.decode(Library.self, forKey: .library)
        counts = (try? c.decodeIfPresent(BackupCounts.self, forKey: .counts)) ?? BackupCounts(library)
        secrets = try c.decodeIfPresent(Data.self, forKey: .secrets)
        passphrase = try? c.decodeIfPresent(PassphraseWrap.self, forKey: .passphrase)
        secretsInClear = try c.decodeIfPresent(Bool.self, forKey: .secretsInClear) ?? false
    }
}

/// What Verify found out about a backup file.
public struct BackupCheck: Equatable, Sendable {
    public var file: BackupFile
    public var url: URL
    /// the library's own problems (repeated ids, too deep…), as Validate reports them
    public var report: ValidationReport
    /// the secrets could be opened (with this Mac's key, the key file chosen, or the passphrase typed)
    public var secretsReadable: Bool
    /// how they were opened, for the sentence
    public var openedWith: String
    /// the secrets, once opened (never written anywhere by Verify)
    public var secrets: [String: String]
    /// sealed secrets are inside (a plain-text backup has none to open)
    public var hasSecrets: Bool { file.secrets != nil }
    public var secretsInClear: Bool { file.secretsInClear && file.counts.secrets > 0 }
    public var canRestore: Bool { report.canImport && (secretsReadable || !hasSecrets) }
    public var acceptsPassphrase: Bool { file.passphrase != nil }
}

public enum Backup {
    public static let currentVersion = 1
    public static let fileExtension = "bmbackup"

    /// The file's bytes: the library with its secrets sealed by `key`, and the key sealed by the passphrase when there is one.
    /// `secretsInClear` writes the secrets as plain text inside the library instead of sealing them — readable by
    /// anyone who has the file.
    public static func make(_ lib: Library, key: SymmetricKey?, passphrase: PassphraseWrap?, reason: BackupReason, now: Date = Date(), kept: Bool = false, note: String = "", secretsInClear: Bool = false) throws -> Data {
        if secretsInClear {
            var f = BackupFile(createdAt: now, reason: reason, counts: BackupCounts(lib), library: lib)
            f.kept = kept; f.note = note; f.secretsInClear = true
            return try JSON.encoder.encode(f)
        }
        var plain = lib
        var values: [String: String] = [:]
        for t in plain.tabs.indices { LibraryStore.strip(&plain.tabs[t], into: &values) }
        var f = BackupFile(createdAt: now, reason: reason, counts: BackupCounts(lib), library: plain)
        f.kept = kept; f.note = note
        if !values.isEmpty {
            guard let key else { throw BMError("The secrets can't go into a backup without this Mac's key (secret.key is missing).") }
            guard let combined = try AES.GCM.seal(JSONEncoder().encode(values), using: key).combined else { throw BMError("The secrets could not be sealed.") }
            f.secrets = combined
        }
        f.passphrase = passphrase
        return try JSON.encoder.encode(f)
    }

    /// Reads a backup file, refusing anything that isn't one.
    public static func read(_ data: Data) throws -> BackupFile {
        let f: BackupFile
        do { f = try JSON.decoder.decode(BackupFile.self, from: data) }
        catch { throw BMError("This isn't a Bookmark Manager backup file (it could not be read as one).") }
        guard f.app == "Bookmark Manager", f.kind == "backup" else { throw BMError("This isn't a Bookmark Manager backup file.") }
        guard f.version >= 1 else { throw BMError("This backup file has no version number, so it can't be trusted.") }
        guard f.version <= currentVersion else { throw BMError("This backup was made by a newer Bookmark Manager (file version \(f.version); this one reads up to \(currentVersion)). Update the app, then restore it.") }
        return f
    }

    /// The secrets inside, opened with a key.
    public static func secrets(in f: BackupFile, key: SymmetricKey) throws -> [String: String] {
        guard let sealed = f.secrets else { return [:] }
        do { return try JSONDecoder().decode([String: String].self, from: AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)) }
        catch { throw BMError("The secrets in this backup don't open with that key.") }
    }

    /// The library with its secrets put back.
    public static func library(_ f: BackupFile, secrets: [String: String]) -> Library {
        if f.secretsInClear { return f.library }
        var lib = f.library
        for t in lib.tabs.indices { LibraryStore.fill(&lib.tabs[t], secrets) }
        return lib
    }

    /// Verify: reads the file, checks the library the way Validate does, and tries the secrets with the key given.
    public static func check(_ data: Data, at url: URL, key: SymmetricKey?, openedWith: String) -> Result<BackupCheck, BMError> {
        let f: BackupFile
        do { f = try read(data) } catch let e as BMError { return .failure(e) } catch { return .failure(BMError(error.localizedDescription)) }
        var secrets: [String: String] = [:]
        var readable = f.secrets == nil
        if let key, f.secrets != nil, let s = try? Backup.secrets(in: f, key: key) { secrets = s; readable = true }
        let filled = library(f, secrets: secrets)
        let report = Transfer.validate(ExportFile(secretsIncluded: readable, library: filled))
        let how = f.secretsInClear ? "nothing: they are in plain text in this file" : (readable ? openedWith : "")
        return .success(BackupCheck(file: f, url: url, report: report, secretsReadable: readable, openedWith: how, secrets: secrets))
    }

    /// "Bookmark Manager 2026-10-29 14-02-33.bmbackup"
    public static func fileName(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Bookmark Manager \(f.string(from: date)).\(fileExtension)"
    }

    /// A fingerprint of everything that would go into a backup, so an unchanged library isn't backed up again.
    public static func digest(_ lib: Library) -> String {
        let data = (try? JSON.encoder.encode(LibraryFile(library: lib))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// One backup in the folder, as the list shows it.
public struct BackupEntry: Identifiable, Equatable, Sendable {
    public var url: URL
    public var createdAt: Date
    public var reason: BackupReason
    public var kept: Bool
    public var note: String
    public var counts: BackupCounts
    public var size: Int
    public var readable: Bool
    public var id: URL { url }
}

/// The folder of backups: listing, writing, keeping, pruning.
public final class BackupStore: @unchecked Sendable {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    /// Every backup in the folder, newest first (a file that isn't one is listed as unreadable, never deleted).
    public func list() -> [BackupEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        var out: [(entry: BackupEntry, written: Date)] = []
        for n in names where n.hasSuffix("." + Backup.fileExtension) {
            let u = folder.appendingPathComponent(n)
            let attrs = (try? FileManager.default.attributesOfItem(atPath: u.path)) ?? [:]
            let size = attrs[.size] as? Int ?? 0
            let written = attrs[.modificationDate] as? Date ?? .distantPast
            if let d = try? Data(contentsOf: u), let f = try? Backup.read(d) {
                out.append((BackupEntry(url: u, createdAt: f.createdAt, reason: f.reason, kept: f.kept, note: f.note, counts: f.counts, size: size, readable: true), written))
            } else {
                out.append((BackupEntry(url: u, createdAt: written, reason: .manual, kept: true, note: "", counts: BackupCounts(Library.fresh()), size: size, readable: false), written))
            }
        }
        // newest first; two made in the same second are told apart by when their files were written
        return out.sorted { a, b in
            if a.entry.createdAt != b.entry.createdAt { return a.entry.createdAt > b.entry.createdAt }
            return a.written > b.written
        }.map(\.entry)
    }

    @discardableResult
    public func write(_ data: Data, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var u = folder.appendingPathComponent(Backup.fileName(date))
        var n = 1
        while FileManager.default.fileExists(atPath: u.path) { n += 1; u = folder.appendingPathComponent(Backup.fileName(date).replacingOccurrences(of: ".\(Backup.fileExtension)", with: " (\(n)).\(Backup.fileExtension)")) }
        try data.write(to: u, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        return u
    }

    /// Marks a backup as kept (never pruned), with a note, or unmarks it — rewriting the file's header fields only.
    public func setKept(_ url: URL, kept: Bool, note: String) throws {
        var f = try Backup.read(try Data(contentsOf: url))
        f.kept = kept; f.note = kept ? note.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        try JSON.encoder.encode(f).write(to: url, options: .atomic)
    }

    /// Deletes the oldest backups beyond `keep`, never a kept one or an unreadable file. Returns what went.
    @discardableResult
    public func prune(keep: Int) -> [URL] {
        let unkept = list().filter { $0.readable && !$0.kept }
        guard unkept.count > keep else { return [] }
        var gone: [URL] = []
        for e in unkept.dropFirst(keep) where (try? FileManager.default.removeItem(at: e.url)) != nil { gone.append(e.url) }
        return gone
    }
}

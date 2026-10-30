import XCTest
import CryptoKit
@testable import BookmarkManagerCore

/// Backups (Matt, Oct 29 2026): the file, the key, the passphrase, the folder, the restore on a fresh Mac.
final class BackupTests: XCTestCase {
    func testABackupHoldsEverythingAndOpensWithTheKey() throws {
        let s = Scratch()
        let store = LibraryStore(folder: s.url)
        let lib = Sample.library()
        try store.save(lib)
        let key = try XCTUnwrap(try store.secrets.currentKey())
        let data = try Backup.make(lib, key: key, passphrase: nil, reason: .manual, now: Date(timeIntervalSince1970: 1_800_000_000), note: "first")
        let f = try Backup.read(data)
        XCTAssertEqual(f.version, 1); XCTAssertEqual(f.reason, .manual); XCTAssertEqual(f.note, "first"); XCTAssertFalse(f.kept)
        XCTAssertEqual(f.counts.bookmarks, lib.allBookmarks.count); XCTAssertEqual(f.counts.secrets, 3)
        XCTAssertTrue(f.library.allBookmarks.allSatisfy { $0.secret.isEmpty }, "no secret in the clear")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("hunter2"), "nor anywhere in the file")
        let secrets = try Backup.secrets(in: f, key: key)
        XCTAssertEqual(secrets.count, 3)
        XCTAssertEqual(Backup.library(f, secrets: secrets), lib, "the library comes back whole")
        XCTAssertThrowsBM(try Backup.secrets(in: f, key: SymmetricKey(size: .bits256)), containing: "don't open with that key")
        // not a backup
        XCTAssertThrowsBM(try Backup.read(try Transfer.export(lib, includeSecrets: false)), containing: "isn't a Bookmark Manager backup")
        XCTAssertThrowsBM(try Backup.read(Data("junk".utf8)), containing: "isn't a Bookmark Manager backup")
        var newer = f; newer.version = 99
        XCTAssertThrowsBM(try Backup.read(try JSON.encoder.encode(newer)), containing: "newer Bookmark Manager")
        XCTAssertEqual(Backup.fileName(Date(timeIntervalSince1970: 0)).hasSuffix(".bmbackup"), true)
    }

    func testThePassphraseOpensTheKeyAndTheWrongOneDoesNot() throws {
        let key = SymmetricKey(size: .bits256)
        XCTAssertThrowsBM(try PassphraseWrap.make(key: key, passphrase: "short"), containing: "at least 8")
        let wrap = try PassphraseWrap.make(key: key, passphrase: "sierra nevada 1987", rounds: 2_000)
        XCTAssertEqual(try wrap.unwrap(passphrase: "sierra nevada 1987"), key)
        XCTAssertThrowsBM(try wrap.unwrap(passphrase: "sierra nevada 1988"), containing: "doesn't open")
        // through a backup: the secrets open with the passphrase alone, no key file
        let lib = Sample.library()
        let data = try Backup.make(lib, key: key, passphrase: wrap, reason: .daily)
        let f = try Backup.read(data)
        let k2 = try XCTUnwrap(f.passphrase).unwrap(passphrase: "sierra nevada 1987")
        XCTAssertEqual(try Backup.secrets(in: f, key: k2).count, 3)
    }

    func testVerifyReportsWhatItCanAndCannotOpen() throws {
        let key = SymmetricKey(size: .bits256)
        let lib = Sample.library()
        let data = try Backup.make(lib, key: key, passphrase: nil, reason: .quit)
        let u = URL(fileURLWithPath: "/tmp/x.bmbackup")
        let withKey = try Backup.check(data, at: u, key: key, openedWith: "this Mac's key").get()
        XCTAssertTrue(withKey.canRestore); XCTAssertTrue(withKey.secretsReadable); XCTAssertEqual(withKey.secrets.count, 3); XCTAssertTrue(withKey.report.canImport)
        let without = try Backup.check(data, at: u, key: nil, openedWith: "").get()
        XCTAssertFalse(without.canRestore); XCTAssertFalse(without.secretsReadable); XCTAssertTrue(without.hasSecrets); XCTAssertFalse(without.acceptsPassphrase)
        let wrong = try Backup.check(data, at: u, key: SymmetricKey(size: .bits256), openedWith: "").get()
        XCTAssertFalse(wrong.secretsReadable)
        // no secrets at all: nothing to open
        var plain = lib
        for t in plain.tabs.indices { plain.tabs[t].bookmarks = plain.tabs[t].bookmarks.map { var b = $0; b.hasSecret = false; b.secret = ""; return b }; plain.tabs[t].folders = [] }
        let noSecrets = try Backup.check(try Backup.make(plain, key: nil, passphrase: nil, reason: .manual), at: u, key: nil, openedWith: "").get()
        XCTAssertTrue(noSecrets.canRestore); XCTAssertFalse(noSecrets.hasSecrets)
        // secrets but no key on this Mac: making the backup refuses rather than dropping them
        XCTAssertThrowsBM(try Backup.make(lib, key: nil, passphrase: nil, reason: .manual), containing: "without this Mac's key")
        // a broken library inside is reported, not restored
        var bad = lib
        bad.tabs[0].bookmarks.append(Bookmark(id: Sample.hig, name: "twin", url: "https://x.example"))
        let broken = try Backup.check(try Backup.make(bad, key: key, passphrase: nil, reason: .manual), at: u, key: key, openedWith: "k").get()
        XCTAssertFalse(broken.canRestore); XCTAssertTrue(broken.report.problems.contains { $0.text.contains("used twice") })
    }

    func testTheFolderListsWritesKeepsAndPrunes() throws {
        let s = Scratch()
        let bs = BackupStore(folder: s.url.appendingPathComponent("Backups"))
        let key = SymmetricKey(size: .bits256)
        let lib = Sample.library()
        var urls: [URL] = []
        for i in 0..<6 {
            let d = try Backup.make(lib, key: key, passphrase: nil, reason: i == 0 ? .manual : .daily, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 86_400))
            urls.append(try bs.write(d, at: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 86_400)))
        }
        XCTAssertEqual(bs.list().count, 6)
        XCTAssertEqual(bs.list().first?.url, urls[5], "newest first")
        // two with the same second get different names
        let twin = try bs.write(try Backup.make(lib, key: key, passphrase: nil, reason: .manual), at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNotEqual(twin, urls[0]); XCTAssertTrue(twin.lastPathComponent.contains("(2)"))
        try FileManager.default.removeItem(at: twin)
        // keep the oldest with a note; a stray file is listed, unreadable, and left alone
        try bs.setKept(urls[0], kept: true, note: "  month start ")
        try Data("not a backup".utf8).write(to: bs.folder.appendingPathComponent("odd.bmbackup"))
        let kept = try XCTUnwrap(bs.list().first { $0.url == urls[0] })
        XCTAssertTrue(kept.kept); XCTAssertEqual(kept.note, "month start")
        XCTAssertEqual(bs.list().filter { !$0.readable }.count, 1)
        let gone = bs.prune(keep: 3)
        XCTAssertEqual(Set(gone), Set([urls[1], urls[2]]), "the oldest unkept ones go; the kept one and the stray stay")
        XCTAssertEqual(bs.list().filter(\.readable).count, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
        try bs.setKept(urls[0], kept: false, note: "")
        XCTAssertEqual(bs.prune(keep: 3).count, 1)
        // the digest changes with a secret, not with nothing
        var changed = lib
        changed.tabs[0].bookmarks[0].secret += "!"
        XCTAssertNotEqual(Backup.digest(lib), Backup.digest(changed))
        XCTAssertEqual(Backup.digest(lib), Backup.digest(Sample.library()))
    }
}

/// The plain-text choice (Matt, Oct 30 2026): the secrets written in the clear, by request only.
final class PlainBackupTests: XCTestCase {
    func testAPlainBackupHoldsTheSecretsInTheClearAndNeedsNoKey() throws {
        let lib = Sample.library()
        let data = try Backup.make(lib, key: nil, passphrase: nil, reason: .manual, secretsInClear: true)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("hunter2"), "that is the point of it")
        let f = try Backup.read(data)
        XCTAssertTrue(f.secretsInClear); XCTAssertNil(f.secrets); XCTAssertEqual(f.counts.secrets, 3)
        XCTAssertEqual(Backup.library(f, secrets: [:]), lib, "the library comes back whole with no key at all")
        let c = try Backup.check(data, at: URL(fileURLWithPath: "/tmp/p.bmbackup"), key: nil, openedWith: "").get()
        XCTAssertTrue(c.canRestore); XCTAssertTrue(c.secretsReadable); XCTAssertTrue(c.secretsInClear); XCTAssertFalse(c.hasSecrets)
        XCTAssertTrue(c.openedWith.contains("plain text"))
        // the default stays sealed, and an old file without the flag reads as sealed
        let sealed = try Backup.read(try Backup.make(lib, key: SymmetricKey(size: .bits256), passphrase: nil, reason: .manual))
        XCTAssertFalse(sealed.secretsInClear)
    }
}

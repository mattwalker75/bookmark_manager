import XCTest
import CryptoKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Backups through the app (Matt, Oct 29 2026): written when something changed, kept, verified, restored —
/// including on a "fresh Mac" (a second scratch home) with the key file or the passphrase.
@MainActor
final class BackupModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; return m }

    func testBackupsAreWrittenWhenSomethingChangedAndPruned() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        XCTAssertEqual(m.backupStore.folder, home.appendingPathComponent("Backups", isDirectory: true), "the default folder is beside the library")
        XCTAssertTrue(m.backUp(reason: .manual)?.hasPrefix("Backed up") ?? false)
        XCTAssertEqual(m.backups.count, 1)
        XCTAssertNil(m.backUp(reason: .daily), "nothing changed: skipped")
        XCTAssertNotNil(m.backUp(reason: .manual, force: true), "by hand: written anyway")
        m.addTab("Another")
        XCTAssertNotNil(m.backUp(reason: .quit))
        XCTAssertEqual(m.backups.count, 3)
        XCTAssertEqual(m.backups.first?.reason, .quit)
        // keep one with a note, prune to 1: the kept one survives
        let oldest = try XCTUnwrap(m.backups.last)
        m.setKept(oldest, kept: true, note: "first ever")
        m.settings.backupKeep = 1
        m.addTab("Yet another"); m.backUp(reason: .change)
        XCTAssertEqual(m.backups.filter(\.kept).count, 1)
        XCTAssertEqual(m.backups.filter { !$0.kept }.count, 1)
        XCTAssertEqual(m.backups.first { $0.kept }?.note, "first ever")
        // the quit hook and the launch rule
        m.settings.backupWhen = .manual
        m.addTab("Quiet"); m.backupOnQuit()
        XCTAssertEqual(m.backups.count, 2, "manual only: the quit writes nothing")
        m.settings.backupWhen = .dailyAndQuit; m.backupOnQuit()
        XCTAssertEqual(m.backups.count, 2, "written, then pruned back to the kept one + the latest")
        XCTAssertEqual(m.backups.first?.reason, .quit)
        m.settings.backupsEnabled = false; m.addTab("Off"); m.backupOnQuit(); m.backupAtLaunchIfDue()
        XCTAssertEqual(m.backups.count, 2, "turned off: nothing")
        XCTAssertEqual(m.backups.first?.reason, .quit)
    }

    func testPlainTextBackupsRestoreAnywhereAndTheChoiceIsRemembered() throws {
        let old = model()
        old.importFileForTest(Sample.library())
        old.setBackupSecretsPlain(true)
        XCTAssertNotNil(old.backUp(reason: .manual))
        let url = try XCTUnwrap(old.backups.first).url
        XCTAssertTrue(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("correct-horse"))
        XCTAssertTrue(AppSettings.load().backupSecretsPlain, "the choice is kept in settings.json")
        // switching back writes a sealed one next time even though nothing else changed
        old.setBackupSecretsPlain(false)
        XCTAssertNotNil(old.backUp(reason: .daily))
        XCTAssertFalse(String(decoding: try Data(contentsOf: try XCTUnwrap(old.backups.first).url), as: UTF8.self).contains("correct-horse"))
        // a fresh Mac restores the plain one with no key and no passphrase
        let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fresh) }
        setenv("BOOKMARKMANAGER_HOME", fresh.path, 1)
        let m = model()
        let c = try m.checkBackup(at: url).get()
        XCTAssertTrue(c.canRestore); XCTAssertTrue(c.secretsInClear)
        XCTAssertTrue(m.restoreBackup(c).hasPrefix("Restored"))
        XCTAssertEqual(m.library.allBookmarks.first { $0.name == "Postgres admin" }?.secret.isEmpty, false)
        XCTAssertEqual(model().library.allBookmarks.first { $0.name == "Postgres admin" }?.secret, Sample.library().allBookmarks.first { $0.name == "Postgres admin" }?.secret, "sealed with the fresh Mac's own key from here on")
    }

    func testRestoreOnAFreshMacWithTheKeyFileOrThePassphrase() throws {
        // the old Mac: a library with secrets, a passphrase, one backup
        let old = model()
        old.importFileForTest(Sample.library())
        try old.setBackupPassphrase("sierra nevada 1987")
        XCTAssertNotNil(old.backUp(reason: .manual, force: true))
        let backup = try XCTUnwrap(old.backups.first).url
        let keyCopy = home.appendingPathComponent("my-key-copy")
        try old.saveKeyCopy(to: keyCopy)
        XCTAssertEqual(try Data(contentsOf: keyCopy).count, 32)
        // the fresh Mac: another home, nothing in it
        let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fresh) }
        setenv("BOOKMARKMANAGER_HOME", fresh.path, 1)
        let m = model()
        XCTAssertEqual(m.library.allBookmarks.count, 0)
        // with this Mac's (new, different) key: the secrets stay shut
        let shut = try m.checkBackup(at: backup).get()
        XCTAssertFalse(shut.canRestore); XCTAssertTrue(shut.hasSecrets); XCTAssertTrue(shut.acceptsPassphrase)
        // a wrong passphrase, a wrong key file
        if case .failure(let e) = m.checkBackup(at: backup, passphrase: "nope nope nope") { XCTAssertTrue(e.message.contains("doesn't open")) } else { XCTFail("accepted a wrong passphrase") }
        try Data("abc".utf8).write(to: fresh.appendingPathComponent("bad.key"))
        if case .failure(let e) = m.checkBackup(at: backup, keyFile: fresh.appendingPathComponent("bad.key")) { XCTAssertTrue(e.message.contains("isn't a Bookmark Manager key file")) } else { XCTFail("accepted a bad key file") }
        // the key file opens it; so does the passphrase
        let withKey = try m.checkBackup(at: backup, keyFile: keyCopy).get()
        let secretCount = Sample.library().allBookmarks.filter(\.hasSecret).count
        XCTAssertTrue(withKey.canRestore); XCTAssertEqual(withKey.secrets.count, secretCount); XCTAssertTrue(withKey.openedWith.contains("my-key-copy"))
        let withWords = try m.checkBackup(at: backup, passphrase: "sierra nevada 1987").get()
        XCTAssertTrue(withWords.canRestore); XCTAssertEqual(withWords.openedWith, "the passphrase")
        // restore: everything is there, the secrets re-sealed with the fresh Mac's own key
        let said = m.restoreBackup(withWords)
        XCTAssertTrue(said.hasPrefix("Restored"), said)
        XCTAssertEqual(m.library.allBookmarks.count, Sample.library().allBookmarks.count)
        XCTAssertEqual(m.library.allBookmarks.first { $0.name == "Postgres admin" }?.secret, Sample.library().allBookmarks.first { $0.name == "Postgres admin" }?.secret)
        let reloaded = model()
        XCTAssertEqual(reloaded.library.allBookmarks.first { $0.name == "Postgres admin" }?.secret, "user: byowner_admin\npassword: correct-horse-battery\n\nrecovery email: ops@example.com\n\nAPI token (read only):\npgat_7f1c9e2ab4d84f0e9c2a")
        XCTAssertTrue(m.backups.isEmpty, "an empty library before the restore: no 'before restore' backup was needed")
        // restoring over something writes a kept 'before restore' backup first
        m.addTab("Mine")
        let again = try m.checkBackup(at: backup, passphrase: "sierra nevada 1987").get()
        _ = m.restoreBackup(again)
        XCTAssertEqual(m.backups.count, 1); XCTAssertEqual(m.backups[0].reason, .beforeRestore); XCTAssertTrue(m.backups[0].kept)
        XCTAssertNil(m.library.tabs.first { $0.name == "Mine" })
    }
}

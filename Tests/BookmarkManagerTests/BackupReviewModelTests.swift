import XCTest
import CryptoKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Review 2 (Oct 30 2026) of the backup / restore / secrets paths through AppModel: the reviewer's cases, each
/// asserting the fixed behaviour. All on scratch homes.
@MainActor
final class BackupReviewModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; return m }
    /// a backup folder that can never be created: a path underneath a plain file
    private func unwritableFolder() throws -> String {
        let f = home.appendingPathComponent("plainfile")
        try Data("x".utf8).write(to: f)
        return f.appendingPathComponent("Backups").path
    }
    private func perms(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.posixPermissions] as? Int) ?? -1 }

    func testRestoreRefusesWhenTheSafetyBackupCouldNotBeWritten() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        let backup = try XCTUnwrap(m.backups.first).url
        m.addTab("Mine, not in the backup")
        m.settings.backupFolder = try unwritableFolder()
        let check = try m.checkBackup(at: backup).get()
        let said = m.restoreBackup(check)
        XCTAssertTrue(said.hasPrefix("Nothing was restored"), said)
        XCTAssertNotNil(m.library.tabs.first { $0.name == "Mine, not in the backup" }, "the library stays as it was")
    }

    func testRestoreSaysNothingWasRestoredWhenTheSaveWasRefused() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        let check = try m.checkBackup(at: try XCTUnwrap(m.backups.first).url).get()
        m.addTab("Mine")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: m.store.url.path)   // something else wrote library.json
        let said = m.restoreBackup(check)
        XCTAssertNotNil(m.library.tabs.first { $0.name == "Mine" })
        XCTAssertTrue(said.hasPrefix("Nothing was restored"), said)
        XCTAssertTrue(said.contains("changed by something else"), said)
    }

    func testADegradedLaunchWritesNoAutomaticBackupAndSaysSoByHand() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        m.settings.backupKeep = 2
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        m.addTab("Two"); XCTAssertNotNil(m.backUp(reason: .manual))
        let good = Set(m.backups.map(\.url))
        try Data("garbage".utf8).write(to: m.store.secrets.dataURL)
        let again = model()
        XCTAssertTrue(again.loadTrouble)
        XCTAssertNil(again.backupOnQuit()); again.backupAtLaunchIfDue()
        again.refreshBackups()
        XCTAssertEqual(Set(again.backups.map(\.url)), good, "both good backups are still there")
        let byHand = try XCTUnwrap(again.backUp(reason: .manual, force: true))
        XCTAssertTrue(byHand.contains("loaded without its secrets"), byHand)
        try Data("{ not json".utf8).write(to: again.store.url)
        let third = model()
        XCTAssertTrue(third.loadTrouble); XCTAssertNil(third.backupOnQuit())
        third.refreshBackups()
        XCTAssertEqual(third.backups.filter { $0.counts.bookmarks == 0 }.count, 0, "no backup of nothing")
    }

    func testAStalePassphraseIsNoticedAndLeftOutOfNewBackups() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        try m.setBackupPassphrase("sierra nevada 1987")
        XCTAssertFalse(m.backupPassphraseStale)
        try Data("garbage".utf8).write(to: m.store.secrets.dataURL)
        let again = model()   // the key was moved aside with the unreadable secrets
        var b = try XCTUnwrap(again.library.allBookmarks.first { $0.name == "Webull" })
        b.secret = "acct 456"; again.updateBookmark(b)   // a new key is made
        XCTAssertTrue(again.backupPassphraseStale)
        XCTAssertNotNil(again.backUp(reason: .manual, force: true))
        let newest = try XCTUnwrap(again.backups.first).url
        XCTAssertNil(try Backup.read(try Data(contentsOf: newest)).passphrase, "a stale wrap goes into no backup")
        if case .failure(let e) = again.checkBackup(at: newest, passphrase: "sierra nevada 1987") { XCTAssertTrue(e.message.contains("no passphrase on it"), e.message) } else { XCTFail("the passphrase should not open it") }
        // an old backup that still carries the stale wrap says what is wrong
        try again.setBackupPassphrase("sierra nevada 1987")
        XCTAssertFalse(again.backupPassphraseStale)
    }

    func testAPassphraseThatOpensTheWrongKeyIsSaidPlainly() throws {
        let a = model()
        a.importFileForTest(Sample.library())
        try a.setBackupPassphrase("sierra nevada 1987")
        XCTAssertNotNil(a.backUp(reason: .manual, force: true))
        let backup = try XCTUnwrap(a.backups.first).url
        // hand-craft the stale case: the wrap from this Mac, the secrets sealed with another key
        var f = try Backup.read(try Data(contentsOf: backup))
        let other = SymmetricKey(size: .bits256)
        f.secrets = try AES.GCM.seal(try JSONEncoder().encode(["x": "y"]), using: other).combined
        let crafted = home.appendingPathComponent("crafted.bmbackup")
        try JSON.encoder.encode(f).write(to: crafted)
        if case .failure(let e) = a.checkBackup(at: crafted, passphrase: "sierra nevada 1987") { XCTAssertTrue(e.message.contains("isn't the key these secrets were sealed with"), e.message) } else { XCTFail("should say the key is the wrong one") }
        if case .failure(let e) = a.checkBackup(at: crafted, keyFile: a.store.secrets.keyURL) { XCTAssertTrue(e.message.contains("isn't the key these secrets were sealed with"), e.message) } else { XCTFail("should say the key file is the wrong one") }
    }

    func testADirectoriesOnlyLibraryGetsItsSafetyBackup() throws {
        let other = model()
        other.importFileForTest(Sample.library())
        XCTAssertNotNil(other.backUp(reason: .manual, force: true))
        let backup = try XCTUnwrap(other.backups.first).url
        let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-review-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fresh) }
        setenv("BOOKMARKMANAGER_HOME", fresh.path, 1)
        let m = model()
        XCTAssertTrue(m.library.isFresh)
        m.renameTab(m.library.tabs[0].id, "Projects")
        for n in ["Alpha", "Beta", "Gamma"] { m.addFolder(name: n, description: "", colorId: nil, in: FolderPath(tab: m.library.tabs[0].id)) }
        XCTAssertFalse(m.library.isFresh)
        let check = try m.checkBackup(at: backup, keyFile: other.store.secrets.keyURL).get()
        XCTAssertTrue(m.restoreBackup(check).hasPrefix("Restored"))
        let before = try XCTUnwrap(m.backups.first { $0.reason == .beforeRestore })
        XCTAssertTrue(before.kept)
        XCTAssertEqual(try m.checkBackup(at: before.url).get().file.library.allFolders.map(\.name).sorted(), ["Alpha", "Beta", "Gamma"])
    }

    func testAFailedQuitBackupIsReportedAndEveryChangeComplainsOncePerHour() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        m.settings.backupFolder = try unwritableFolder()
        m.addTab("Two")
        let problem = m.backupOnQuit()
        XCTAssertTrue(problem?.contains("could not") ?? false || problem != nil, "the quit is told: \(problem ?? "nil")")
        XCTAssertTrue(m.backups.isEmpty)
        m.settings.backupWhen = .everyChange
        var alerts = 0
        for n in ["A", "B", "C"] { m.notice = nil; m.addTab(n); if m.notice?.title == "The backup could not be written" { alerts += 1 } }
        XCTAssertEqual(alerts, 1, "once, not on every change")
    }

    func testAfterDeletingEveryBackupTheNextQuitWritesOne() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        for e in m.backups { m.deleteBackup(e) }
        XCTAssertTrue(m.backups.isEmpty)
        m.backupOnQuit()
        XCTAssertEqual(m.backups.count, 1)
    }

    func testBackUpNowWorksWithBackupsOffAndSettingsAre0600() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        m.settings.backupsEnabled = false
        XCTAssertTrue(m.backUp(reason: .manual, force: true)?.hasPrefix("Backed up") ?? false)
        try m.setBackupPassphrase("sierra nevada 1987")
        let text = try String(contentsOf: AppSettings.url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"wrapped\"")); XCTAssertFalse(text.contains("sierra nevada"))
        XCTAssertEqual(perms(AppSettings.url), 0o600)
    }

    func testRestoreWithSecretWindowsOpen() throws {
        _ = NSApplication.shared
        let m = model()
        m.importFileForTest(Sample.library())
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        let backup = try XCTUnwrap(m.backups.first).url
        let pg = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "Postgres admin" })
        let local = Bookmark(name: "Local only", url: "https://local.example", hasSecret: true, secret: "s")
        m.addBookmark(local, in: FolderPath(tab: m.library.tabs[0].id))
        SecretWindows.show(pg, model: m); SecretWindows.show(local, model: m)
        _ = m.restoreBackup(try m.checkBackup(at: backup).get())
        XCTAssertTrue(SecretWindows.isOpen(pg.id), "still in the library: its window stays")
        XCTAssertFalse(SecretWindows.isOpen(local.id), "gone with the restore: its window is closed")
        SecretWindows.close(pg.id)
    }

    func testWhatWorks() throws {
        let m = model()
        var lib = Sample.library()
        lib.tabs[1].bookmarks.append(Bookmark(name: "Blank one", url: "https://blank.example", hasSecret: true, secret: ""))
        m.importFileForTest(lib)
        XCTAssertNotNil(m.backUp(reason: .manual, force: true))
        let backupURL = try XCTUnwrap(m.backups.first).url
        let backupText = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertFalse(backupText.contains("correct-horse")); XCTAssertFalse(backupText.contains("MintyFresh")); XCTAssertEqual(perms(backupURL), 0o600)
        m.addBookmark(Bookmark(name: "Local only", url: "https://local.example", hasSecret: true, secret: "local-secret-xyz"), in: FolderPath(tab: m.library.tabs[0].id))
        var pg = try XCTUnwrap(m.library.allBookmarks.first { $0.name == "Postgres admin" }); pg.secret = "changed-after-backup"; m.updateBookmark(pg)
        let check = try m.checkBackup(at: backupURL).get()
        XCTAssertTrue(check.report.problems.contains { $0.text.contains("secret is blank") })
        _ = m.restoreBackup(check)
        XCTAssertNil(m.library.allBookmarks.first { $0.name == "Local only" })
        let pgSecret = Sample.library().allBookmarks.first { $0.name == "Postgres admin" }!.secret
        XCTAssertEqual(m.library.allBookmarks.first { $0.name == "Postgres admin" }?.secret, pgSecret, "the edit made after the backup is undone")
        XCTAssertEqual(m.library.allBookmarks.first { $0.name == "Blank one" }?.secret, "", "the backup's blank wins")
        let before = try XCTUnwrap(m.backups.first { $0.reason == .beforeRestore })
        XCTAssertTrue(before.kept)
        XCTAssertEqual(try m.checkBackup(at: before.url).get().secrets.values.contains("local-secret-xyz"), true, "the local-only secret is in the kept before-restore backup")
        XCTAssertFalse(try String(contentsOf: before.url, encoding: .utf8).contains("local-secret-xyz"), "sealed, not in the clear")
        let reloaded = model()
        XCTAssertEqual(reloaded.library.allBookmarks.first { $0.name == "Postgres admin" }?.secret, pgSecret, "next launch reads the re-sealed secrets")
        XCTAssertNil(reloaded.store.problem)
    }
}

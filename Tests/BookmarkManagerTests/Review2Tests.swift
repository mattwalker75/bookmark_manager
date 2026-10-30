import XCTest
import AppKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// Review 2 (Oct 30 2026): the gaps the docs reviewer found, each pinned down.
@MainActor
final class Review2Tests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-r2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; m.importFileForTest(Sample.library()); return m }

    func testTheQuitHookIsWhatTheDelegateRuns() {
        var ran = 0
        AppDelegate.beforeQuit = { ran += 1 }
        defer { AppDelegate.beforeQuit = nil }
        XCTAssertEqual(AppDelegate().applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertEqual(ran, 1)
    }

    func testTheDailyBackupComesWhenTheLastOneIsADayOldAndNotBefore() throws {
        let m = model()
        XCTAssertNotNil(m.backUp(reason: .manual))
        m.addTab("Later")
        m.backupAtLaunchIfDue()
        XCTAssertEqual(m.backups.count, 1, "a fresh backup: nothing yet")
        m.settings.lastBackupAt = Date().addingTimeInterval(-25 * 3_600)
        m.backupAtLaunchIfDue()
        XCTAssertEqual(m.backups.count, 2); XCTAssertEqual(m.backups.first?.reason, .daily)
        m.settings.lastBackupAt = Date().addingTimeInterval(-25 * 3_600)
        m.backupAtLaunchIfDue()
        XCTAssertEqual(m.backups.count, 2, "a day old but nothing changed: skipped")
        // "every day" alone ignores quit; "after every change" writes at most once an hour
        m.settings.backupWhen = .daily; m.addTab("Q"); m.backupOnQuit()
        XCTAssertEqual(m.backups.count, 2)
        m.settings.backupWhen = .everyChange
        m.settings.lastBackupAt = Date()
        m.addTab("Change 1")
        XCTAssertEqual(m.backups.count, 2, "the last backup is recent: the change waits")
        m.settings.lastBackupAt = Date().addingTimeInterval(-2 * 3_600)
        m.addTab("Change 2")
        XCTAssertEqual(m.backups.count, 3); XCTAssertEqual(m.backups.first?.reason, .change)
        m.addTab("Change 3")
        XCTAssertEqual(m.backups.count, 3, "and not again within the hour")
    }

    func testTheNewSettingsFieldsReadBadValuesSafely() throws {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let s = try d.decode(AppSettings.self, from: Data(#"{"linkCheckDays":-5,"backupKeep":0,"backupFolder":"","backupWhen":"whenever","backupPassphrase":"junk","lastBackupAt":"not a date","backupSecretsPlain":"yes"}"#.utf8))
        XCTAssertEqual(s.linkCheckDays, 0); XCTAssertEqual(s.backupKeep, 1); XCTAssertNil(s.backupFolder)
        XCTAssertEqual(s.backupWhen, .dailyAndQuit); XCTAssertNil(s.backupPassphrase); XCTAssertNil(s.lastBackupAt)
        XCTAssertTrue(s.backupsEnabled); XCTAssertFalse(s.backupSecretsPlain, "a wrong type for one value never throws the whole file away")
        let older = try d.decode(AppSettings.self, from: Data(#"{"appearance":"dark","fetchIcons":"maybe","browser":"","secretHideMinutes":"ten"}"#.utf8))
        XCTAssertEqual(older.appearance, .dark); XCTAssertTrue(older.fetchIcons); XCTAssertNil(older.browser); XCTAssertEqual(older.secretHideMinutes, 5)
        // prune never takes every unkept backup, even when told to keep none
        let bs = BackupStore(folder: home.appendingPathComponent("B"))
        let lib = Sample.library()
        for i in 0..<3 { _ = try bs.write(try Backup.make(lib, key: nil, passphrase: nil, reason: .manual, secretsInClear: true), at: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(bs.prune(keep: 0).count, 2); XCTAssertEqual(bs.list().count, 1)
    }

    func testAOneDirectoryCheckKeepsTheOtherMarksAndTheSummaryAddsUp() async throws {
        let server = try TinyHTTP { _, path in path == "/gone" ? "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" : "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
        defer { server.stop() }
        let m = model()
        // every bookmark moved to its tab's top level and pointed at this Mac; the first web bookmark of the first
        // two tabs that have one answers 404
        var lib = m.library
        for t in lib.tabs.indices {
            lib.tabs[t].bookmarks = lib.tabs[t].allBookmarks.map { var b = $0; if !b.isSecretOnly { b.url = "http://127.0.0.1:\(server.port)/fine" }; return b }
            lib.tabs[t].folders = []
        }
        var marked: [Int] = []
        for t in lib.tabs.indices where marked.count < 2 {
            if let i = lib.tabs[t].bookmarks.firstIndex(where: { !$0.isSecretOnly }) { lib.tabs[t].bookmarks[i].url = "http://127.0.0.1:\(server.port)/gone"; marked.append(t) }
        }
        XCTAssertEqual(marked.count, 2)
        let work = lib.tabs[marked[0]]
        m.importFileForTest(lib)
        m.checkLinks(inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        let all = try XCTUnwrap(m.linkReport)
        XCTAssertEqual(all.problems.count, 2)
        XCTAssertTrue(all.summary.hasPrefix("2 of \(all.checked)"))
        // now only the Work tab: Home's mark stays, and the numbers still add up
        m.checkLinks(in: FolderPath(tab: work.id), inMainWindow: false)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        let scoped = try XCTUnwrap(m.linkReport)
        XCTAssertEqual(Set(scoped.problems.map(\.bookmarkId)), Set(all.problems.map(\.bookmarkId)))
        XCTAssertGreaterThanOrEqual(scoped.checked, scoped.problems.count, scoped.summary)
        XCTAssertEqual(scoped.checked, m.library.tab(work.id)!.allBookmarks.filter { !$0.isSecretOnly }.count + 1)
        XCTAssertNil(scoped.scope); XCTAssertFalse(scoped.automatic)
    }

    func testTheMissingBrowserIsMentionedOncePerBookmark() throws {
        let m = model()
        let b = Bookmark(name: "x", url: "https://x.example", browser: "com.example.gone")
        var told = 0
        for _ in 0..<3 { if m.browserChoice(for: b) { _ in false }.note != nil { told += 1 } }
        XCTAssertEqual(told, 3, "the choice itself always carries the note; open() is what says it once")
    }
}

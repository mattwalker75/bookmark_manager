import XCTest
import AppKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// The deep review of Nov 8 2026 (five reviewers), app side: each case asserts the fixed behaviour. Scratch homes only.
@MainActor
final class Review3ModelTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-review3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }
    private func model() -> AppModel { let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false; return m }

    /// A bookmark typed without a scheme (or with an upper-case one) is checked, marked, and can take a new address.
    func testTheMarksFollowTheAddressAsTyped() async throws {
        let server = try TinyHTTP { _, path in
            if path.hasPrefix("/moved") { return "HTTP/1.1 301 Moved Permanently\r\nLocation: /new\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
            return "HTTP/1.1 \(path == "/new" ? "200 OK" : "404 Not Found")\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        defer { server.stop() }
        let m = model()
        var lib = Library.fresh(); let tab = FolderPath(tab: lib.tabs[0].id)
        let plain = UUID(), upper = UUID(), spaced = UUID()
        try lib.addBookmark(Bookmark(id: plain, name: "No scheme", url: "127.0.0.1:\(server.port)/gone"), in: tab)
        try lib.addBookmark(Bookmark(id: upper, name: "Upper", url: "HTTP://127.0.0.1:\(server.port)/gone"), in: tab)
        try lib.addBookmark(Bookmark(id: spaced, name: "Moved", url: "http://127.0.0.1:\(server.port)/moved page"), in: tab)
        m.importFileForTest(lib)
        m.checkLinks()
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        let r = try XCTUnwrap(m.linkReport)
        XCTAssertEqual(r.checked, 3, "the upper-case scheme is checked too")
        XCTAssertEqual(Set(m.linkProblems.keys), [plain, upper, spaced], "every row wears its mark")
        // Use new address on the one typed with a space: taken, not refused as "changed since"
        let moved = try XCTUnwrap(r.problems.first { $0.bookmarkId == spaced })
        m.useNewAddress(moved)
        XCTAssertNil(m.notice); XCTAssertEqual(m.library.bookmark(spaced)?.url, "http://127.0.0.1:\(server.port)/new")
    }

    /// One directory of dead sites is reported as such, not thrown away as "no connection".
    func testADirectoryOfDeadSitesIsReportedNotDiscarded() async throws {
        let m = model()
        var lib = Library.fresh(); let tab = FolderPath(tab: lib.tabs[0].id)
        let dir = try lib.addFolder(name: "Old projects", description: "", colorId: nil, in: tab)
        let path = FolderPath([lib.tabs[0].id, dir])
        for i in 0..<2 { _ = try lib.addBookmark(Bookmark(name: "Dead \(i)", url: "http://127.0.0.1:\(2100 + i)/"), in: path) }
        _ = try lib.addBookmark(Bookmark(name: "Elsewhere", url: "http://127.0.0.1:2199/"), in: tab)
        m.importFileForTest(lib)
        m.checkLinks(in: path)
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNil(m.linkNote, "a scoped check of dead sites is not 'no connection'")
        XCTAssertEqual(m.linkReport?.problems.count, 2); XCTAssertTrue(m.linkReport?.scope?.hasSuffix("Old projects") ?? false)
        // the whole library, every address dead: that is still read as this Mac's connection
        m.checkLinks()
        while m.linkCheckRunning { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(m.linkNote); XCTAssertEqual(m.linkReport?.problems.count, 2, "the last report stays")
    }

    func testAFailedImportIsNilAndTheSettingsFileIsWatched() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        // another copy wrote library.json: the import's save is refused, and the caller is told nil, not "no notes"
        let other = LibraryStore(folder: home); var lib = try other.load(); lib.tabs[0].name = "Touched"; try other.save(lib)
        let before = m.library
        XCTAssertNil(m.importFile(ExportFile(secretsIncluded: true, library: Library.fresh()), mode: .replace))
        XCTAssertEqual(m.library, before); XCTAssertEqual(m.notice?.title, "The bookmarks could not be saved")
        // settings.json that cannot be written: said, not swallowed
        m.notice = nil
        try FileManager.default.removeItem(at: AppSettings.url)
        try FileManager.default.createDirectory(at: AppSettings.url, withIntermediateDirectories: false)
        m.settings.browser = "com.apple.Safari"
        XCTAssertEqual(m.notice?.title, "The settings could not be saved")
        try FileManager.default.removeItem(at: AppSettings.url)
        // settings.json that is not JSON: moved aside and said, not written over
        try Data("{not json".utf8).write(to: AppSettings.url)
        let again = model()
        XCTAssertEqual(again.notice?.title, "The settings could not be read")
        XCTAssertTrue(again.notice?.message.contains("settings.json.unreadable-") ?? false)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: home.path).filter { $0.hasPrefix("settings.json.unreadable-") }.isEmpty)
    }

    func testANewBackupFolderGetsTheNextAutomaticBackup() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        m.settings.backupsEnabled = true; m.settings.backupWhen = .dailyAndQuit
        XCTAssertNotNil(m.backUp(reason: .manual))
        let fresh = home.appendingPathComponent("elsewhere", isDirectory: true)
        m.setBackupFolder(fresh.path)
        XCTAssertNil(m.settings.lastBackupDigest)
        XCTAssertNil(m.backupOnQuit(), "no problem writing it — nothing changed, but the new folder has nothing yet")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fresh.path).filter { $0.hasSuffix(".bmbackup") }.isEmpty)
        m.setBackupFolder(fresh.path)
        XCTAssertNotNil(m.settings.lastBackupDigest, "the same folder again changes nothing")
    }

    func testDeletingNotesClosesTheWindowOnlyWhenTheyAreGone() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        let pm = try XCTUnwrap(m.library.allBookmarks.first { $0.hasNotes })
        NotesWindows.show(pm, model: m)
        defer { NotesWindows.close(pm.id) }
        let other = LibraryStore(folder: home); var lib = try other.load(); lib.tabs[0].name = "Touched"; try other.save(lib)
        m.deleteNotes(pm.id)
        XCTAssertEqual(m.notice?.title, "The bookmarks could not be saved")
        XCTAssertTrue(m.library.bookmark(pm.id)?.hasNotes ?? false); XCTAssertTrue(NotesWindows.isOpen(pm.id), "the window stays with the notes")
    }

    func testTheNotesWindowKeepsItsLinksAndRefitsAfterSave() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        let pm = try XCTUnwrap(m.library.allBookmarks.first { $0.hasNotes && $0.notes.contains("http") })
        NotesWindows.show(pm, model: m)
        defer { NotesWindows.close(pm.id) }
        let holder = try XCTUnwrap(NotesWindows.holder(pm.id))
        func links() -> Int {
            guard let tv = holder.window?.contentView?.firstTextView else { return -1 }
            var n = 0
            tv.textStorage?.enumerateAttribute(.link, in: NSRange(location: 0, length: tv.textStorage?.length ?? 0)) { v, _, _ in if v != nil { n += 1 } }
            return n
        }
        holder.window?.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(links(), 0, "read mode: the addresses are links")
        holder.beginEdit(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        holder.cancelEdit(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(links(), 0, "back from Edit → Cancel the addresses are links again")
        // Save with much more text: the window grows to fit
        let before = holder.fitted
        holder.beginEdit(); holder.draft = pm.notes + "\n" + Array(repeating: "another line of notes", count: 25).joined(separator: "\n")
        XCTAssertTrue(holder.save())
        XCTAssertGreaterThan(holder.fitted.height, before.height, "refitted after the save")
        XCTAssertEqual(holder.window?.contentView?.frame.size.height, holder.fitted.height)
    }

    /// A front page bigger than the cap is read up to the cap (its <head> is at the front); one many times bigger is left alone.
    func testABigFrontPageIsReadUpToTheCap() async throws {
        let body = Data(repeating: 0x20, count: 600_000)
        let server = try TinyHTTP { _, path in
            let n = path == "/huge" ? 50_000_000 : 600_000
            return "HTTP/1.1 200 OK\r\nContent-Length: \(n)\r\nConnection: close\r\n\r\n" + String(decoding: body, as: UTF8.self)
        }
        defer { server.stop() }
        let data = await IconFetcher.read(IconFetcher.request(URL(string: "http://127.0.0.1:\(server.port)/")!, accept: "text/html"), upTo: 300_000, partial: true)
        XCTAssertEqual(data?.count, 300_000)
        let huge = await IconFetcher.read(IconFetcher.request(URL(string: "http://127.0.0.1:\(server.port)/huge")!, accept: "text/html"), upTo: 300_000, partial: true)
        XCTAssertNil(huge)
        let image = await IconFetcher.read(IconFetcher.request(URL(string: "http://127.0.0.1:\(server.port)/icon.png")!, accept: "image/*"), upTo: 300_000)
        XCTAssertNil(image, "an image bigger than its cap is of no use in part")
    }

    func testEditFromAReportWindowNeverReplacesAnOpenEditor() throws {
        let m = model()
        m.importFileForTest(Sample.library())
        let a = m.library.allBookmarks[0], b = m.library.allBookmarks[1]
        ReportWindows.edit(a, model: m)
        XCTAssertEqual(m.sheet?.id, "editBookmark-\(a.id)")
        ReportWindows.edit(b, model: m)
        XCTAssertEqual(m.sheet?.id, "editBookmark-\(a.id)", "the open editor stays; a second Edit… does not replace it")
        m.sheet = nil
        ReportWindows.edit(b, model: m)
        XCTAssertEqual(m.sheet?.id, "editBookmark-\(b.id)")
        m.sheet = nil
    }
}

private extension NSView {
    var firstTextView: NSTextView? {
        if let t = self as? NSTextView { return t }
        for s in subviews { if let t = s.firstTextView { return t } }
        return nil
    }
}

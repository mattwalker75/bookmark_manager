import XCTest
import AppKit
@testable import BookmarkManager
@testable import BookmarkManagerCore

/// The text size of secret and notes windows (Matt, Nov 8 2026): Settings' defaults, ⌘+ ⌘− ⌘0 in a window,
/// the window refitting to its text at the new size.
@MainActor
final class TextSizeTests: XCTestCase {
    private var home: URL!
    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarkmanager-textsize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("BOOKMARKMANAGER_HOME", home.path, 1)
    }
    override func tearDown() async throws { unsetenv("BOOKMARKMANAGER_HOME"); try? FileManager.default.removeItem(at: home) }

    func testTheSettingsHoldTheDefaultsAndForgiveBadValues() throws {
        XCTAssertEqual(AppSettings().secretTextSize, 14); XCTAssertEqual(AppSettings().notesTextSize, 14)
        let json = #"{"secretTextSize": 200, "notesTextSize": -3}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.secretTextSize, 36, "pulled into the range"); XCTAssertEqual(s.notesTextSize, 9)
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(missing.secretTextSize, 14); XCTAssertEqual(missing.notesTextSize, 14)
        XCTAssertEqual(AppSettings.clampText(14), 14); XCTAssertEqual(AppSettings.clampText(0), 9); XCTAssertEqual(AppSettings.clampText(99), 36)
        // the keys: + and = are bigger (no shift needed), − and _ smaller, 0 back; anything else is not ours
        XCTAssertEqual(TextSizeKeys.step(for: "+"), 1); XCTAssertEqual(TextSizeKeys.step(for: "="), 1)
        XCTAssertEqual(TextSizeKeys.step(for: "-"), -1); XCTAssertEqual(TextSizeKeys.step(for: "_"), -1)
        XCTAssertEqual(TextSizeKeys.step(for: "0"), 0); XCTAssertNil(TextSizeKeys.step(for: "a")); XCTAssertNil(TextSizeKeys.step(for: ""))
    }

    func testAWindowFitsItsTextAtTheSizeItIsGiven() {
        let screen = NSSize(width: 1440, height: 900)
        let text = (1...8).map { "line \($0): a fairly long line of secret text, wider than the floor" }.joined(separator: "\n")
        let small = SecretWindows.fittedSize(for: text, screen: screen, size: 12)
        let big = SecretWindows.fittedSize(for: text, screen: screen, size: 24)
        XCTAssertGreaterThan(big.width, small.width); XCTAssertGreaterThan(big.height, small.height)
        XCTAssertEqual(SecretWindows.fittedSize(for: text, screen: screen), SecretWindows.fittedSize(for: text, screen: screen, size: 14), "the default is 14 points")
        let notes = Array(repeating: "a line of notes that is long enough to matter here", count: 6).joined(separator: "\n")
        XCTAssertGreaterThan(NotesWindows.fittedSize(for: notes, screen: screen, size: 30).height, NotesWindows.fittedSize(for: notes, screen: screen, size: 10).height)
        // the fonts the windows draw with are the sizes asked for
        XCTAssertEqual(SecretWindows.font(20).pointSize, 20); XCTAssertEqual(NotesWindows.font(11).pointSize, 11)
        XCTAssertTrue(SecretWindows.font(20).isFixedPitch, "secrets stay monospaced")
    }

    func testBiggerSmallerAndBackInAnOpenWindow() throws {
        let m = AppModel(); m.settings.fetchIcons = false; m.icons.enabled = false
        m.importFileForTest(Sample.library())
        m.settings.secretTextSize = 16; m.settings.notesTextSize = 18
        // the longest secret, so the window has rows to grow by (a one-line secret fits the floor at any size)
        let secret = try XCTUnwrap(m.library.allBookmarks.filter(\.hasSecret).max { $0.secret.count < $1.secret.count })
        let notes = try XCTUnwrap(m.library.allBookmarks.first { $0.hasNotes })
        SecretWindows.show(secret, model: m)
        NotesWindows.show(notes, model: m)
        defer { SecretWindows.close(secret.id); NotesWindows.close(notes.id) }
        XCTAssertEqual(SecretWindows.textSize(secret.id), 16, "opens at Settings' size"); XCTAssertEqual(NotesWindows.textSize(notes.id), 18)
        let sw = try XCTUnwrap(NSApp.windows.first { $0.title == "Secret · \(secret.name)" })
        let nw = try XCTUnwrap(NSApp.windows.first { $0.title == "Notes · \(notes.name)" })
        let before = sw.contentView!.frame.size
        XCTAssertTrue(SecretWindows.adjustText(in: sw, by: 1)); XCTAssertEqual(SecretWindows.textSize(secret.id), 18)
        XCTAssertTrue(SecretWindows.adjustText(in: sw, by: 1)); XCTAssertEqual(SecretWindows.textSize(secret.id), 20)
        XCTAssertGreaterThan(sw.contentView!.frame.size.height, before.height, "the window grew to fit the bigger text")
        XCTAssertTrue(SecretWindows.adjustText(in: sw, by: 0)); XCTAssertEqual(SecretWindows.textSize(secret.id), 16, "⌘0 is Settings' size")
        XCTAssertFalse(SecretWindows.adjustText(in: nw, by: 1), "a notes window is not a secret window")
        XCTAssertTrue(NotesWindows.adjustText(in: nw, by: -1)); XCTAssertEqual(NotesWindows.textSize(notes.id), 16)
        for _ in 0..<30 { NotesWindows.adjustText(in: nw, by: -1) }
        XCTAssertEqual(NotesWindows.textSize(notes.id), 9, "never below the range")
        for _ in 0..<30 { NotesWindows.adjustText(in: nw, by: 1) }
        XCTAssertEqual(NotesWindows.textSize(notes.id), 36, "never above it")
        // the key monitor's reading of an event: ⌘= on the notes window makes it bigger; the same key with ⌥ is left alone
        NotesWindows.adjustText(in: nw, by: 0)
        let e = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: nw.windowNumber, context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertTrue(TextSizeKeys.handle(e)); XCTAssertEqual(NotesWindows.textSize(notes.id), 20)
        let alt = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: nw.windowNumber, context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
        XCTAssertFalse(TextSizeKeys.handle(alt))
        // a window that is neither: not ours
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        XCTAssertFalse(SecretWindows.adjustText(in: other, by: 1)); XCTAssertFalse(NotesWindows.adjustText(in: other, by: 1))
    }
}

// ⌘+ ⌘− ⌘0 in a secret window or a notes window (Matt, Nov 8 2026): bigger, smaller, back to the size from
// Settings — for that one window, while it is open. One local key monitor for all of them; the View menu has the
// same three items (enabled while such a window is key). Nothing else in the app is touched by these keys.
import AppKit

@MainActor
enum TextSizeKeys {
    /// points per press
    static let step = 2
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in handle(e) ? nil : e }
    }

    /// True when the key was used up: ⌘ with + (or =, so the shift key isn't needed), − or 0, in a secret or notes
    /// window; the keypad's + and − too.
    static func handle(_ e: NSEvent) -> Bool {
        guard let w = e.window, e.modifierFlags.contains(.command), e.modifierFlags.intersection([.control, .option]).isEmpty else { return false }
        guard let step = step(for: e.charactersIgnoringModifiers ?? "") else { return false }
        return SecretWindows.adjustText(in: w, by: step) || NotesWindows.adjustText(in: w, by: step)
    }
    /// +1 for "+" or "=", −1 for "−" or "_", 0 for "0"; nil for anything else
    static func step(for chars: String) -> Int? {
        switch chars { case "+", "=": return 1; case "-", "_": return -1; case "0": return 0; default: return nil }
    }
    /// The View menu's items: the key window, when it is a secret or notes window.
    static func adjustKeyWindow(by step: Int) {
        guard let w = NSApp.keyWindow else { return }
        if !SecretWindows.adjustText(in: w, by: step) { NotesWindows.adjustText(in: w, by: step) }
    }
}

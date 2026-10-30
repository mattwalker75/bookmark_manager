// The secret window: a small window of its own with the bookmark's secret as selectable text (Matt: no Copy
// button — select the word you need and copy it, or double-click it). Hide closes it. One window per bookmark;
// it follows edits and closes when the bookmark goes.
import SwiftUI
import AppKit
import BookmarkManagerCore

@MainActor
enum SecretWindows {
    private static var windows: [UUID: NSWindow] = [:]
    private static var holders: [UUID: SecretHolder] = [:]

    /// the smallest the window is ever made (the tip line and the buttons fit)
    static let floor = NSSize(width: 420, height: 180)
    /// the font the secret is shown in (the sizing below measures with the same one)
    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize + 1, weight: .regular)

    /// The window size that shows the whole secret without scrolling: the text measured in its font plus the
    /// chrome around it, never smaller than `floor`, never wider than 60% or taller than 70% of `screen` (Matt,
    /// Oct 29 2026: grow to fit, up to a cap). A secret longer than that scrolls inside.
    static func fittedSize(for text: String, screen: NSSize) -> NSSize {
        let lines = text.isEmpty ? [SecretView.emptyText] : text.components(separatedBy: "\n")
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let widest = lines.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        // around the text: the view's padding (16 each side), the text view's inset (6) and line padding (5), the scroller and bezel
        let width = widest + 2 * 16 + 2 * 6 + 2 * 5 + 20
        // above and below it: padding, the tip row, two gaps, the buttons, the text view's inset, the bezel
        let height = CGFloat(lines.count) * lineHeight + 2 * 16 + 20 + 2 * 12 + 28 + 2 * 8 + 4
        let cap = NSSize(width: max(floor.width, (screen.width * 0.6).rounded(.down)), height: max(floor.height, (screen.height * 0.7).rounded(.down)))
        return NSSize(width: min(max(width, floor.width), cap.width), height: min(max(height, floor.height), cap.height))
    }

    private static func screenSize() -> NSSize {
        let s = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        return s?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
    }

    static func isOpen(_ id: UUID) -> Bool { windows[id] != nil }

    /// The window hides itself after Settings' minutes without being used (0 = never); using it again restarts the clock.
    static func arm(_ id: UUID) {
        guard let holder = holders[id] else { return }
        holder.timer?.invalidate(); holder.timer = nil
        let minutes = holder.model?.settings.secretHideMinutes ?? 0
        guard minutes > 0 else { return }
        holder.timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60, repeats: false) { _ in
            MainActor.assumeIsolated { SecretWindows.close(id) }
        }
    }

    static func show(_ b: Bookmark, model: AppModel) {
        if let w = windows[b.id] { holders[b.id]?.bookmark = b; w.makeKeyAndOrderFront(nil); arm(b.id); return }
        let holder = SecretHolder(bookmark: b)
        holder.model = model
        let view = SecretView(holder: holder, model: model).environmentObject(model).environmentObject(model.icons)
        let size = fittedSize(for: b.secret, screen: screenSize())
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Secret · \(b.name)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.minSize = floor
        w.center()
        w.delegate = Closer.shared
        holder.fitted = size
        windows[b.id] = w; holders[b.id] = holder
        w.makeKeyAndOrderFront(nil)
        arm(b.id)
    }

    /// The bookmark changed: the open window shows the new text and title, and fits the new text again unless
    /// the window was resized by hand.
    static func refresh(_ b: Bookmark) {
        guard let w = windows[b.id], let holder = holders[b.id] else { return }
        if !b.hasSecret { close(b.id); return }
        let textChanged = holder.bookmark.secret != b.secret
        holder.bookmark = b
        w.title = "Secret · \(b.name)"
        if textChanged, let content = w.contentView, content.frame.size == holder.fitted {
            let size = fittedSize(for: b.secret, screen: screenSize())
            w.setContentSize(size)
            holder.fitted = size
        }
    }

    static func close(_ id: UUID) { windows[id]?.close() }

    fileprivate static func forget(_ w: NSWindow) {
        guard let id = windows.first(where: { $0.value === w })?.key else { return }
        holders[id]?.timer?.invalidate()
        windows.removeValue(forKey: id); holders.removeValue(forKey: id)
    }

    fileprivate static func used(_ w: NSWindow) {
        guard let id = windows.first(where: { $0.value === w })?.key else { return }
        arm(id)
    }

    private final class Closer: NSObject, NSWindowDelegate {
        static let shared = Closer()
        func windowWillClose(_ n: Notification) {
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { SecretWindows.forget(w) }
        }
        // brought forward or clicked into: the hide-after clock starts again
        func windowDidBecomeKey(_ n: Notification) {
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { SecretWindows.used(w) }
        }
    }
}

final class SecretHolder: ObservableObject {
    @Published var bookmark: Bookmark
    /// the size the window was given to fit its text (a window still this size follows the text when it changes)
    var fitted = NSSize.zero
    /// hides the window after Settings' minutes
    var timer: Timer?
    weak var model: AppModel?
    init(bookmark: Bookmark) { self.bookmark = bookmark }
}

struct SecretView: View {
    @ObservedObject var holder: SecretHolder
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    static let emptyText = "(No secret has been typed for this bookmark yet. Edit the bookmark to add it.)"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").foregroundStyle(Theme.accent)
                Text("Select any part and copy it. Hide puts it away again.").font(DS.secondary).foregroundStyle(.secondary)
            }
            ReadOnlyText(text: holder.bookmark.secret.isEmpty ? SecretView.emptyText : holder.bookmark.secret, muted: holder.bookmark.secret.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Edit bookmark…") {
                    model.sheet = .editBookmark(holder.bookmark)
                    NSApp.windows.first { $0.identifier?.rawValue == "main" || $0.title == "Bookmark Manager" }?.makeKeyAndOrderFront(nil)
                }
                Button("Hide") { SecretWindows.close(holder.bookmark.id) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .font(DS.body)
        .preferredColorScheme(model.lookInForce.colorScheme)
        .tint(Theme.accent)
    }
}

/// Selectable, uneditable text in a bezel: the secret, exactly as typed (monospaced, so 0 and O tell apart).
struct ReadOnlyText: NSViewRepresentable {
    let text: String
    var muted = false
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = SecretWindows.font
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.setAccessibilityLabel("The secret")
        apply(tv)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { if let tv = scroll.documentView as? NSTextView { apply(tv) } }
    private func apply(_ tv: NSTextView) {
        if tv.string != text { tv.string = text }
        tv.textColor = muted ? .secondaryLabelColor : .labelColor
    }
}

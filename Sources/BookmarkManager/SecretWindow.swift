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

    static func show(_ b: Bookmark, model: AppModel) {
        if let w = windows[b.id] { holders[b.id]?.bookmark = b; w.makeKeyAndOrderFront(nil); return }
        let holder = SecretHolder(bookmark: b)
        let view = SecretView(holder: holder, model: model).environmentObject(model).environmentObject(model.icons)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Secret · \(b.name)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.minSize = NSSize(width: 360, height: 220)
        w.center()
        w.delegate = Closer.shared
        windows[b.id] = w; holders[b.id] = holder
        w.makeKeyAndOrderFront(nil)
    }

    /// The bookmark changed: the open window shows the new text and title.
    static func refresh(_ b: Bookmark) {
        guard let w = windows[b.id] else { return }
        if !b.hasSecret { close(b.id); return }
        holders[b.id]?.bookmark = b
        w.title = "Secret · \(b.name)"
    }

    static func close(_ id: UUID) { windows[id]?.close() }

    fileprivate static func forget(_ w: NSWindow) {
        guard let id = windows.first(where: { $0.value === w })?.key else { return }
        windows.removeValue(forKey: id); holders.removeValue(forKey: id)
    }

    private final class Closer: NSObject, NSWindowDelegate {
        static let shared = Closer()
        func windowWillClose(_ n: Notification) {
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { SecretWindows.forget(w) }
        }
    }
}

final class SecretHolder: ObservableObject {
    @Published var bookmark: Bookmark
    init(bookmark: Bookmark) { self.bookmark = bookmark }
}

struct SecretView: View {
    @ObservedObject var holder: SecretHolder
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").foregroundStyle(Theme.accent)
                Text("Select any part and copy it. Hide puts it away again.").font(DS.secondary).foregroundStyle(.secondary)
            }
            ReadOnlyText(text: holder.bookmark.secret.isEmpty ? "(No secret has been typed for this bookmark yet. Edit the bookmark to add it.)" : holder.bookmark.secret, muted: holder.bookmark.secret.isEmpty)
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
        tv.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize + 1, weight: .regular)
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

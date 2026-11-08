// The notes window (Matt, Nov 8 2026; mockup board "Notes window A"): a window of its own per bookmark with the
// bookmark's notes — plain text for yourself, not a secret. It opens read-only (no accidental typing); Edit turns
// the text box on, then Cancel / Save (⌘S). Closing with unsaved changes asks "Save your changes?"; Delete notes…
// asks first and turns the bookmark's notes off. It never hides by itself, it sizes itself to its text like the
// secret window, and it follows edits made elsewhere while it isn't being edited.
import SwiftUI
import AppKit
import BookmarkManagerCore

@MainActor
enum NotesWindows {
    private static var windows: [UUID: NSWindow] = [:]
    private static var holders: [UUID: NotesHolder] = [:]

    /// the smallest the window is ever made (the tip line and the buttons fit)
    static let floor = NSSize(width: 440, height: 220)
    /// notes are prose: the system font, not the secrets' monospaced one
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)

    /// The window size that shows the whole text without scrolling (measured in its font plus the chrome), never
    /// smaller than `floor`, never wider than 60% or taller than 70% of `screen`. Longer notes scroll inside.
    static func fittedSize(for text: String, screen: NSSize) -> NSSize {
        let shown = text.isEmpty ? NotesView.emptyText : text
        let lines = shown.components(separatedBy: "\n")
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let widest = lines.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        let chromeWidth: CGFloat = 2 * 16 + 2 * 6 + 2 * 5 + 20
        let cap = NSSize(width: max(floor.width, (screen.width * 0.6).rounded(.down)), height: max(floor.height, (screen.height * 0.7).rounded(.down)))
        let width = min(max(widest + chromeWidth, floor.width), cap.width)
        let textWidth = width - chromeWidth
        let wrapped = (shown as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        let rows = max(CGFloat(lines.count) * lineHeight, ceil(wrapped))
        let height = rows + 2 * 16 + 20 + 2 * 12 + 28 + 2 * 8 + 4
        return NSSize(width: width, height: min(max(height, floor.height), cap.height))
    }

    private static func screenSize() -> NSSize {
        let s = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        return s?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
    }

    static func isOpen(_ id: UUID) -> Bool { windows[id] != nil }
    static func holder(_ id: UUID) -> NotesHolder? { holders[id] }
    /// the bookmarks whose notes window is being edited and differs from what is saved
    static var unsavedIds: [UUID] { holders.filter { $0.value.isDirty }.map(\.key) }

    static func show(_ b: Bookmark, model: AppModel) {
        guard b.hasNotes else { return }
        if let w = windows[b.id] { holders[b.id]?.bookmark = b; w.makeKeyAndOrderFront(nil); return }
        let holder = NotesHolder(bookmark: b)
        holder.model = model
        let view = NotesView(holder: holder, model: model).environmentObject(model).environmentObject(model.icons)
        let size = fittedSize(for: b.notes, screen: screenSize())
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Notes · \(b.name)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.minSize = floor
        w.center()
        w.delegate = Closer.shared
        holder.fitted = size
        holder.window = w
        windows[b.id] = w; holders[b.id] = holder
        w.makeKeyAndOrderFront(nil)
    }

    /// The bookmark changed elsewhere: the title follows; the text follows unless it is being edited here
    /// (the edit in hand wins when it is saved); the window refits unless it was resized by hand.
    static func refresh(_ b: Bookmark) {
        guard let w = windows[b.id], let holder = holders[b.id] else { return }
        if !b.hasNotes { holder.editing = false; close(b.id); return }
        let textChanged = holder.bookmark.notes != b.notes
        holder.bookmark = b
        w.title = "Notes · \(b.name)"
        if textChanged, !holder.editing, let content = w.contentView, content.frame.size == holder.fitted {
            let size = fittedSize(for: b.notes, screen: screenSize())
            w.setContentSize(size)
            holder.fitted = size
        }
    }

    static func close(_ id: UUID) { windows[id]?.close() }

    fileprivate static func forget(_ w: NSWindow) {
        guard let id = windows.first(where: { $0.value === w })?.key else { return }
        windows.removeValue(forKey: id); holders.removeValue(forKey: id)
    }

    /// Before the app quits: every notes window with unsaved changes is saved, or the quit is called off.
    /// True = go on quitting.
    static func settleBeforeQuit() -> Bool {
        let dirty = holders.values.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        let n = dirty.count
        let a = NSAlert()
        a.messageText = n == 1 ? "The notes for “\(dirty[0].bookmark.name)” have unsaved changes" : "\(n) notes windows have unsaved changes"
        a.informativeText = "Save keeps what you typed; Quit Without Saving puts the notes back the way they were."
        a.addButton(withTitle: n == 1 ? "Save and Quit" : "Save All and Quit")
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: "Quit Without Saving")
        switch a.runModal() {
        case .alertFirstButtonReturn: return dirty.allSatisfy { $0.save() }
        case .alertThirdButtonReturn: for h in dirty { h.cancelEdit() }; return true
        default: return false
        }
    }

    private final class Closer: NSObject, NSWindowDelegate {
        static let shared = Closer()
        func windowWillClose(_ n: Notification) {
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { NotesWindows.forget(w) }
        }
        /// Closing with changes in hand asks first (the window's own sheet): Save / Don't Save / Cancel.
        func windowShouldClose(_ w: NSWindow) -> Bool {
            MainActor.assumeIsolated {
                guard let id = windows.first(where: { $0.value === w })?.key, let h = holders[id], h.isDirty else { return true }
                let a = NSAlert()
                a.messageText = "Save your changes to the notes for “\(h.bookmark.name)”?"
                a.informativeText = "You edited the notes. Save keeps what you typed; Don’t Save puts the notes back the way they were."
                a.addButton(withTitle: "Save")
                a.addButton(withTitle: "Cancel")
                a.addButton(withTitle: "Don’t Save")
                a.beginSheetModal(for: w) { r in
                    MainActor.assumeIsolated {
                        switch r {
                        case .alertFirstButtonReturn: if h.save() { w.close() }
                        case .alertThirdButtonReturn: h.cancelEdit(); w.close()
                        default: break
                        }
                    }
                }
                return false
            }
        }
    }
}

@MainActor
final class NotesHolder: ObservableObject {
    @Published var bookmark: Bookmark { didSet { updateEdited() } }
    /// the text box is on (Edit was clicked); `draft` is what is being typed
    @Published var editing = false { didSet { updateEdited() } }
    @Published var draft = "" { didSet { updateEdited() } }
    /// the size the window was given to fit its text (a window still this size follows the text when it changes)
    var fitted = NSSize.zero
    weak var model: AppModel?
    weak var window: NSWindow?
    init(bookmark: Bookmark) { self.bookmark = bookmark }

    var isDirty: Bool { editing && draft != bookmark.notes }
    /// the macOS dot in the close button
    private func updateEdited() { window?.isDocumentEdited = isDirty }

    func beginEdit() { draft = bookmark.notes; editing = true }
    func cancelEdit() { editing = false; draft = bookmark.notes }
    /// Saves the draft through the model; false when the save was refused (the window stays as it is).
    @discardableResult
    func save() -> Bool {
        guard let model else { return false }
        guard model.saveNotes(bookmark.id, draft) else { return false }
        if let b = model.library.bookmark(bookmark.id) { bookmark = b }
        editing = false
        return true
    }
}

struct NotesView: View {
    @ObservedObject var holder: NotesHolder
    @ObservedObject var model: AppModel
    static let emptyText = "(No notes have been typed for this bookmark yet. Click Edit to add some.)"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(Theme.accent)
                Text(holder.editing ? "Type your changes. Save keeps them (⌘S); Cancel puts the notes back." : "Plain notes for yourself. They stay open as long as you like; Edit to change them.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            NotesText(text: $holder.draft, shown: holder.bookmark.notes.isEmpty ? NotesView.emptyText : holder.bookmark.notes, editable: holder.editing, muted: holder.bookmark.notes.isEmpty, openLink: { model.openLinkFromNotes($0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Text(lastEdited).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if holder.editing {
                    Button("Cancel") { holder.cancelEdit() }.keyboardShortcut(.cancelAction)
                    Button("Save") { holder.save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!holder.isDirty)
                } else {
                    if !holder.bookmark.isSecretOnly { Button("Open bookmark") { model.open(holder.bookmark) }.help("Open the bookmark in the browser") }
                    Button("Delete notes…") { askDelete() }
                    Button("Edit") { holder.beginEdit() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .font(DS.body)
        .preferredColorScheme(model.lookInForce.colorScheme)
        .tint(Theme.accent)
    }

    private var lastEdited: String {
        guard let d = holder.bookmark.notesEditedAt else { return "" }
        let lines = holder.bookmark.notes.isEmpty ? 0 : holder.bookmark.notes.components(separatedBy: "\n").count
        return "Last edited \(d.formatted(date: .abbreviated, time: .shortened))" + (lines > 0 ? " · \(lines) line\(lines == 1 ? "" : "s")" : "")
    }

    /// Delete notes…: asked first (Cancel is the default, as every delete in the app); the bookmark stays.
    private func askDelete() {
        guard let w = holder.window else { return }
        let lines = holder.bookmark.notes.isEmpty ? 0 : holder.bookmark.notes.components(separatedBy: "\n").count
        let a = NSAlert()
        a.messageText = "Delete the notes for “\(holder.bookmark.name)”?"
        a.informativeText = "The bookmark stays; only its notes\(lines > 0 ? " (\(lines) line\(lines == 1 ? "" : "s"))" : "") are thrown away. This can't be undone."
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: "Delete notes")
        let id = holder.bookmark.id
        a.beginSheetModal(for: w) { r in
            MainActor.assumeIsolated { if r == .alertSecondButtonReturn { model.deleteNotes(id) } }
        }
    }
}

/// The notes text: selectable with clickable addresses while reading; a plain text box while editing (spelling
/// checked, no smart quotes or dashes — notes may hold commands and addresses that must stay as typed).
struct NotesText: NSViewRepresentable {
    @Binding var text: String
    /// what is shown while not editing
    let shown: String
    let editable: Bool
    var muted = false
    let openLink: (URL) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NotesWindows.font
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.setAccessibilityLabel("The notes")
        apply(tv, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let tv = scroll.documentView as? NSTextView { apply(tv, context: context) }
    }
    private func apply(_ tv: NSTextView, context: Context) {
        if editable {
            let wasReading = !tv.isEditable
            tv.isEditable = true; tv.isSelectable = true
            if wasReading || (tv.window?.firstResponder !== tv && tv.string != text) {
                tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: NotesWindows.font, .foregroundColor: NSColor.labelColor]))
            }
            if wasReading { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv); tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0)) } }
        } else {
            tv.isEditable = false; tv.isSelectable = true
            if tv.string != shown || context.coordinator.lastMuted != muted {
                tv.textStorage?.setAttributedString(NotesText.linked(shown, muted: muted))
                context.coordinator.lastMuted = muted
            }
        }
    }
    /// The text with every web address made clickable.
    static func linked(_ s: String, muted: Bool) -> NSAttributedString {
        let a = NSMutableAttributedString(string: s, attributes: [.font: NotesWindows.font, .foregroundColor: muted ? NSColor.secondaryLabelColor : NSColor.labelColor])
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in det.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
                if let u = m.url, ["http", "https", "mailto"].contains(u.scheme?.lowercased() ?? "") { a.addAttribute(.link, value: u, range: m.range) }
            }
        }
        return a
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesText
        var lastMuted: Bool?
        init(_ p: NotesText) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView, parent.editable else { return }
            let value = tv.string
            DispatchQueue.main.async { [self] in if parent.text != value { parent.text = value } }
        }
        func textView(_ tv: NSTextView, clickedOnLink link: Any, at i: Int) -> Bool {
            guard let u = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            parent.openLink(u); return true
        }
    }
}

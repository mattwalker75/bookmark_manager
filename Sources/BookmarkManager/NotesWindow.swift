// The notes window (Matt, Nov 8 2026; mockup board "Notes window A"): a window of its own per bookmark — or per
// directory (Matt, Nov 8 2026: notes on directories too) — with its notes: plain text for yourself, not a secret. It opens read-only (no accidental typing); Edit turns
// the text box on, then Cancel / Save (⌘S). Closing with unsaved changes asks "Save your changes?"; Delete notes…
// asks first and turns the bookmark's notes off. It never hides by itself, it sizes itself to its text like the
// secret window, and it follows edits made elsewhere while it isn't being edited.
import SwiftUI
import AppKit
import BookmarkManagerCore

/// What a notes window shows: a bookmark's notes, or a directory's. The same window either way.
struct NotesItem: Equatable {
    var id: UUID
    var name: String
    var hasNotes: Bool
    var notes: String
    var editedAt: Date?
    var isFolder: Bool
    /// the bookmark itself, for the Open bookmark button (nil for a directory)
    var bookmark: Bookmark?
    init(_ b: Bookmark) { id = b.id; name = b.name; hasNotes = b.hasNotes; notes = b.notes; editedAt = b.notesEditedAt; isFolder = false; bookmark = b }
    init(_ f: Folder) { id = f.id; name = f.name; hasNotes = f.hasNotes; notes = f.notes; editedAt = f.notesEditedAt; isFolder = true; bookmark = nil }
    /// "bookmark" or "directory", for the sentences
    var what: String { isFolder ? "directory" : "bookmark" }
}

@MainActor
enum NotesWindows {
    private static var windows: [UUID: NSWindow] = [:]
    private static var holders: [UUID: NotesHolder] = [:]

    /// the smallest the window is ever made (the tip line and the buttons fit)
    static let floor = NSSize(width: 440, height: 220)
    /// notes are prose: the system font, not the secrets' monospaced one — at `size` points (Settings' notes text
    /// size; ⌘+ ⌘− in the window, Matt, Nov 8 2026)
    nonisolated static func font(_ size: Int) -> NSFont { NSFont.systemFont(ofSize: CGFloat(size)) }
    /// the model the windows belong to (for the View menu's text-size items)
    static weak var model: AppModel?

    /// The window size that shows the whole text without scrolling (measured in its font plus the chrome), never
    /// smaller than `floor`, never wider than 60% or taller than 70% of `screen`. Longer notes scroll inside.
    static func fittedSize(for text: String, screen: NSSize, size: Int = AppSettings.defaultTextSize) -> NSSize {
        let font = NotesWindows.font(size)
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

    static func show(_ b: Bookmark, model: AppModel) { show(NotesItem(b), model: model) }
    static func show(folder f: Folder, model: AppModel) { show(NotesItem(f), model: model) }
    static func show(_ item: NotesItem, model: AppModel) {
        guard item.hasNotes else { return }
        if let w = windows[item.id] { holders[item.id]?.item = item; w.makeKeyAndOrderFront(nil); return }
        let holder = NotesHolder(item: item, textSize: model.settings.notesTextSize)
        holder.model = model
        NotesWindows.model = model
        let view = NotesView(holder: holder, model: model).environmentObject(model).environmentObject(model.icons)
        let size = fittedSize(for: item.notes, screen: screenSize(), size: holder.textSize)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Notes · \(item.name)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.minSize = floor
        w.center()
        w.delegate = Closer.shared
        holder.fitted = size
        holder.window = w
        windows[item.id] = w; holders[item.id] = holder
        w.makeKeyAndOrderFront(nil)
    }

    /// The bookmark (or directory) changed elsewhere: the title follows; the text follows unless it is being
    /// edited here (the edit in hand wins when it is saved); the window refits unless it was resized by hand.
    static func refresh(_ b: Bookmark) { refresh(NotesItem(b)) }
    static func refresh(folder f: Folder) { refresh(NotesItem(f)) }
    static func refresh(_ item: NotesItem) {
        guard let w = windows[item.id], let holder = holders[item.id] else { return }
        if !item.hasNotes { holder.editing = false; close(item.id); return }
        let textChanged = holder.item.notes != item.notes
        holder.item = item
        w.title = "Notes · \(item.name)"
        if textChanged, !holder.editing, let content = w.contentView, content.frame.size == holder.fitted {
            let size = fittedSize(for: item.notes, screen: screenSize(), size: holder.textSize)
            w.setContentSize(size)
            holder.fitted = size
        }
    }

    /// ⌘+ ⌘− ⌘0 in a notes window (Matt, Nov 8 2026): the text size of that one window, two points a step;
    /// 0 = back to Settings' size. True when `w` is a notes window (the key was used up).
    @discardableResult
    static func adjustText(in w: NSWindow, by step: Int) -> Bool {
        guard let id = windows.first(where: { $0.value === w })?.key, let holder = holders[id] else { return false }
        let base = holder.model?.settings.notesTextSize ?? AppSettings.defaultTextSize
        setTextSize(id, step == 0 ? base : holder.textSize + step * TextSizeKeys.step)
        return true
    }
    static func textSize(_ id: UUID) -> Int? { holders[id]?.textSize }
    /// development hook: every open window at once
    static func setTextSizeEverywhere(_ size: Int) { for id in windows.keys { setTextSize(id, size) } }
    static func setTextSize(_ id: UUID, _ size: Int) {
        guard let w = windows[id], let holder = holders[id] else { return }
        let clamped = AppSettings.clampText(size)
        guard clamped != holder.textSize else { return }
        holder.textSize = clamped
        // the window fits its text again at the new size, unless it was resized by hand (or is being typed in)
        if !holder.editing, let content = w.contentView, content.frame.size == holder.fitted {
            let s = fittedSize(for: holder.item.notes, screen: screenSize(), size: clamped)
            w.setContentSize(s); holder.fitted = s
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
        a.messageText = n == 1 ? "The notes for “\(dirty[0].item.name)” have unsaved changes" : "\(n) notes windows have unsaved changes"
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
        func windowDidBecomeKey(_ n: Notification) { MainActor.assumeIsolated { NotesWindows.model?.textWindowIsKey = true } }
        func windowDidResignKey(_ n: Notification) { MainActor.assumeIsolated { NotesWindows.model?.textWindowIsKey = false } }
        /// Closing with changes in hand asks first (the window's own sheet): Save / Don't Save / Cancel.
        func windowShouldClose(_ w: NSWindow) -> Bool {
            MainActor.assumeIsolated {
                guard let id = windows.first(where: { $0.value === w })?.key, let h = holders[id], h.isDirty else { return true }
                let a = NSAlert()
                a.messageText = "Save your changes to the notes for “\(h.item.name)”?"
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
    @Published var item: NotesItem { didSet { updateEdited() } }
    /// the text box is on (Edit was clicked); `draft` is what is being typed
    @Published var editing = false { didSet { updateEdited() } }
    @Published var draft = "" { didSet { updateEdited() } }
    /// the text size of this window (points): Settings' size to begin with, then ⌘+ ⌘− ⌘0
    @Published var textSize: Int
    /// the size the window was given to fit its text (a window still this size follows the text when it changes)
    var fitted = NSSize.zero
    weak var model: AppModel?
    weak var window: NSWindow?
    init(item: NotesItem, textSize: Int = AppSettings.defaultTextSize) { self.item = item; self.textSize = textSize }
    convenience init(bookmark: Bookmark, textSize: Int = AppSettings.defaultTextSize) { self.init(item: NotesItem(bookmark), textSize: textSize) }

    var isDirty: Bool { editing && draft != item.notes }
    /// the macOS dot in the close button
    private func updateEdited() { window?.isDocumentEdited = isDirty }

    func beginEdit() { draft = item.notes; editing = true }
    func cancelEdit() { editing = false; draft = item.notes }
    /// Saves the draft through the model; false when the save was refused (the window stays as it is).
    @discardableResult
    func save() -> Bool {
        guard let model else { return false }
        guard model.saveNotes(item.id, draft) else { return false }
        if let saved = model.notesItem(item.id) { item = saved }
        editing = false
        return true
    }
}

struct NotesView: View {
    @ObservedObject var holder: NotesHolder
    @ObservedObject var model: AppModel
    static let emptyText = "(No notes have been typed here yet. Click Edit to add some.)"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(Theme.accent)
                Text(holder.editing ? "Type your changes. Save keeps them (⌘S); Cancel puts the notes back." : "Plain notes for yourself. They stay open as long as you like; Edit to change them.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            NotesText(text: $holder.draft, shown: holder.item.notes.isEmpty ? NotesView.emptyText : holder.item.notes, editable: holder.editing, muted: holder.item.notes.isEmpty, font: NotesWindows.font(holder.textSize), openLink: { model.openLinkFromNotes($0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Text(lastEdited).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if holder.editing {
                    Button("Cancel") { holder.cancelEdit() }.keyboardShortcut(.cancelAction)
                    Button("Save") { holder.save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!holder.isDirty)
                } else {
                    if let b = holder.item.bookmark, !b.isSecretOnly { Button("Open bookmark") { model.open(b) }.help("Open the bookmark in the browser") }
                    if holder.item.isFolder { Button("Show directory") { model.revealFolder(holder.item.id) }.help("Open the directory in the main window") }
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
        guard let d = holder.item.editedAt else { return "" }
        let lines = holder.item.notes.isEmpty ? 0 : holder.item.notes.components(separatedBy: "\n").count
        return "Last edited \(d.formatted(date: .abbreviated, time: .shortened))" + (lines > 0 ? " · \(lines) line\(lines == 1 ? "" : "s")" : "")
    }

    /// Delete notes…: asked first (Cancel is the default, as every delete in the app); the bookmark or directory stays.
    private func askDelete() {
        guard let w = holder.window else { return }
        let lines = holder.item.notes.isEmpty ? 0 : holder.item.notes.components(separatedBy: "\n").count
        let a = NSAlert()
        a.messageText = "Delete the notes for “\(holder.item.name)”?"
        a.informativeText = "The \(holder.item.what) stays; only its notes\(lines > 0 ? " (\(lines) line\(lines == 1 ? "" : "s"))" : "") are thrown away. This can't be undone."
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: "Delete notes")
        let id = holder.item.id
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
    var font: NSFont = NotesWindows.font(AppSettings.defaultTextSize)
    let openLink: (URL) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = font
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
                tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            }
            // ⌘+ ⌘− while typing: plain text, so the one font covers it all
            if tv.font != font { tv.font = font; tv.textStorage?.addAttribute(.font, value: font, range: NSRange(location: 0, length: tv.textStorage?.length ?? 0)) }
            if wasReading { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv); tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0)) } }
        } else {
            tv.isEditable = false; tv.isSelectable = true
            if tv.string != shown || context.coordinator.lastMuted != muted || context.coordinator.lastFont != font {
                tv.textStorage?.setAttributedString(NotesText.linked(shown, muted: muted, font: font))
                context.coordinator.lastMuted = muted; context.coordinator.lastFont = font
            }
        }
    }
    /// The text with every web address made clickable.
    static func linked(_ s: String, muted: Bool, font: NSFont = NotesWindows.font(AppSettings.defaultTextSize)) -> NSAttributedString {
        let a = NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: muted ? NSColor.secondaryLabelColor : NSColor.labelColor])
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
        var lastFont: NSFont?
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

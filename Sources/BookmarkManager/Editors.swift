// The sheets that make and change things: a bookmark (name, description, address, tags, color, secret, where it
// lives), a directory (name, description, color), a tab's name, and Move to…. Each checks its own fields and shows
// the reason in place, so the sheet never closes on a refusal.
import SwiftUI
import BookmarkManagerCore

// MARK: - a bookmark

struct BookmarkEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @State private var bookmark: Bookmark
    @State private var tagsText: String
    @State private var destination: FolderPath
    private let original: FolderPath
    @State private var problem: String?
    @State private var confirmDelete = false

    init(bookmark: Bookmark?, path: FolderPath) {
        isNew = bookmark == nil
        let b = bookmark ?? Bookmark(name: "", url: "")
        _bookmark = State(initialValue: b)
        _tagsText = State(initialValue: b.tagsText)
        _destination = State(initialValue: path)
        original = path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isNew ? "New bookmark" : "Edit “\(bookmark.name)”").font(DS.heading).lineLimit(1)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Close without saving").accessibilityLabel("Close")
            }
            Form {
                Field("Name", $bookmark.name, "People Manager")
                Field("Description", $bookmark.description, "Optional — a sentence or two, shown under the name")
                LabeledContent("Address") {
                    HStack(spacing: 8) {
                        PlainTextField("https://example.com/page", text: $bookmark.url, monospaced: true, label: "Address")
                        SiteIcon(address: bookmark.url, size: 24)
                    }
                }
                Field("Tags", $tagsText, "Optional — words for the search, separated by commas")
                Text("Tags are only used by the search; they never show on the row.").font(DS.secondary).foregroundStyle(.secondary)
                LabeledContent("Color") { ColorPills(selection: $bookmark.colorId) }
                DestinationPicker(title: "In", selection: $destination)
                Section {
                    Toggle("This bookmark has a secret", isOn: $bookmark.hasSecret)
                    if bookmark.hasSecret {
                        TextBox(text: $bookmark.secret, placeholder: "user name on one line, password on the next, blank lines between…", minLines: 4, maxLines: 10, label: "The secret")
                        Text("Several lines, blank lines included. Kept encrypted on this Mac; shown only when you click Secret; left out of an export unless you tick the box.")
                            .font(DS.secondary).foregroundStyle(.secondary)
                    }
                }
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew { Button("Delete…") { confirmDelete = true } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add bookmark" : "Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 600, height: bookmark.hasSecret ? 700 : 560)
        .confirmationDialog("Delete the bookmark “\(bookmark.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteBookmark(bookmark.id); dismiss() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text(bookmark.hasSecret ? "Its secret goes with it." : "This can't be undone.") }
    }

    private func save() {
        var b = bookmark
        b.tags = Bookmark.parseTags(tagsText)
        // try it on a copy first, so a refusal shows here instead of closing the sheet
        var trial = model.library
        do {
            if isNew { try trial.addBookmark(b, in: destination) }
            else {
                try trial.updateBookmark(b)
                if destination != original { try trial.move(.bookmark(b.id), to: destination) }
            }
        } catch { problem = (error as? BMError)?.message ?? error.localizedDescription; return }
        if isNew { model.addBookmark(b, in: destination) }
        else {
            model.updateBookmark(b)
            if destination != original { model.move(.bookmark(b.id), to: destination) }
        }
        if destination != model.selectedPath { model.select(destination) }
        model.flash(b.id)
        dismiss()
    }
}

/// None, then every color code as a capsule with its dot and name; the chosen one is filled with its tint.
struct ColorPills: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: UUID?

    var body: some View {
        FlowRow(spacing: 6) {
            pill(nil, name: "None", color: nil)
            ForEach(model.library.colors) { c in pill(c.id, name: c.name, color: c.rgb.color) }
            if model.library.colors.isEmpty { Text("No color codes yet — make some in Settings → Color codes.").font(DS.secondary).foregroundStyle(.secondary) }
        }
    }

    private func pill(_ id: UUID?, name: String, color: Color?) -> some View {
        let on = selection == id
        return Button { selection = id } label: {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(name).font(DS.secondary).fontWeight(on ? .semibold : .regular)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(on ? (color?.opacity(scheme == .dark ? 0.32 : 0.20) ?? Theme.accent.opacity(0.14)) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? (color ?? Theme.accent) : DS.edge(scheme), lineWidth: on ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Lays its children out in rows, wrapping like words.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

/// Every tab and directory as "Tab › Directory › Sub-directory", to pick where something goes.
struct DestinationPicker: View {
    @EnvironmentObject var model: AppModel
    let title: String
    @Binding var selection: FolderPath
    /// leave out this folder and everything in it (a directory can't move into itself)
    var excluding: FolderPath? = nil

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices, id: \.path) { c in Text(c.name).tag(c.path) }
        }
    }

    private var choices: [(path: FolderPath, name: String)] {
        var out: [(FolderPath, String)] = []
        for t in model.library.tabs { walk(t, path: FolderPath(tab: t.id), names: [t.name], into: &out) }
        return out
    }
    private func walk(_ f: Folder, path: FolderPath, names: [String], into out: inout [(FolderPath, String)]) {
        if let ex = excluding, path.isInside(ex) { return }
        out.append((path, names.joined(separator: " › ")))
        for sub in f.folders { walk(sub, path: path.appending(sub.id), names: names + [sub.name], into: &out) }
    }
}

// MARK: - a directory

struct FolderEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let path: FolderPath
    @State private var folder: Folder
    @State private var problem: String?
    @State private var confirmDelete = false

    init(folder: Folder?, path: FolderPath) {
        isNew = folder == nil
        self.path = path
        _folder = State(initialValue: folder ?? Folder(name: ""))
    }

    private var level: Int { isNew ? path.depth + 1 : path.depth }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New \(Library.levelName(level))" : "Edit “\(folder.name)”").font(DS.heading).lineLimit(1)
            Text(isNew ? "In \(model.placeName(path))." : "In \(model.placeName(path.parent ?? path)). A \(Library.levelName(level)) can hold bookmarks\(level < model.library.maxDepth ? " and \(Library.levelName(level + 1).replacingOccurrences(of: "directory", with: "directories"))" : "").")
                .font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Field("Name", $folder.name, "Self-hosted apps")
                Field("Description", $folder.description, "Optional — shown under the name")
                LabeledContent("Color") { ColorPills(selection: $folder.colorId) }
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew { Button("Delete…") { tryDelete() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add \(Library.levelName(level))" : "Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 520, height: 340)
        .confirmationDialog("Delete the \(Library.levelName(level)) “\(folder.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteFolder(folder.id); dismiss() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text("It is empty, so nothing else is lost.") }
    }

    private func save() {
        var trial = model.library
        do {
            if isNew { _ = try trial.addFolder(name: folder.name, description: folder.description, colorId: folder.colorId, in: path) }
            else { try trial.updateFolder(folder.id, name: folder.name, description: folder.description, colorId: folder.colorId) }
        } catch { problem = (error as? BMError)?.message ?? error.localizedDescription; return }
        if isNew { model.addFolder(name: folder.name, description: folder.description, colorId: folder.colorId, in: path) }
        else { model.updateFolder(folder.id, name: folder.name, description: folder.description, colorId: folder.colorId) }
        dismiss()
    }

    private func tryDelete() {
        guard let now = model.library.folder(folder.id) else { dismiss(); return }
        if now.isEmpty { confirmDelete = true; return }
        var trial = model.library
        do { try trial.deleteFolder(folder.id) } catch { problem = (error as? BMError)?.message ?? error.localizedDescription }
    }
}

// MARK: - a tab

struct TabNameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let tab: Folder?
    @State private var name: String
    @State private var problem: String?
    init(tab: Folder?) { self.tab = tab; _name = State(initialValue: tab?.name ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tab == nil ? "New tab" : "Rename the tab “\(tab!.name)”").font(DS.heading).lineLimit(1)
            Text(tab == nil ? "A tab is the top level: bookmarks go straight into it, or into directories you make inside it." : "Everything in the tab stays as it is.")
                .font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Field("Name", $name, "Work")
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tab == nil ? "Add tab" : "Rename") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { problem = "The tab needs a name."; return }
                    if let t = tab { model.renameTab(t.id, name) } else { model.addTab(name) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 460)
    }
}

// MARK: - Move to…

struct MoveSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: DragItem
    @State private var destination: FolderPath
    @State private var problem: String?

    init(item: DragItem) {
        self.item = item
        _destination = State(initialValue: FolderPath(tab: UUID()))
    }

    private var name: String {
        switch item { case .bookmark(let id): return model.library.bookmark(id)?.name ?? "?"; case .folder(let id): return model.library.folder(id)?.name ?? "?" }
    }
    private var current: FolderPath? {
        switch item { case .bookmark(let id): return model.library.location(ofBookmark: id); case .folder(let id): return model.library.path(toFolder: id)?.parent }
    }
    private var excluding: FolderPath? { if case .folder(let id) = item { return model.library.path(toFolder: id) }; return nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move “\(name)”").font(DS.heading).lineLimit(1)
            if let current { Text("Now in \(model.placeName(current)).").font(DS.secondary).foregroundStyle(.secondary) }
            Form {
                DestinationPicker(title: "To", selection: $destination, excluding: excluding)
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") {
                    var trial = model.library
                    do { try trial.move(item, to: destination) } catch { problem = (error as? BMError)?.message ?? error.localizedDescription; return }
                    model.move(item, to: destination)
                    model.select(destination); model.flash(item.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(destination == current)
            }
        }
        .padding(20).frame(width: 500)
        .onAppear { if let c = current { destination = c } }
    }
}

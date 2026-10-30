// The main window — Matt's pick, layout A "Tabs on top, folder tree left": the search box in the title bar,
// the tabs across the top, the selected tab's directories and sub-directories down the left (with their
// descriptions), and the selected directory's sub-directories and bookmarks on the right. A click on a bookmark's
// name opens it; a Secret button opens the secret window; rows are tinted with their color code. Everything can
// be dragged: a bookmark or directory onto another directory in the tree, onto a tab, or before another row.
import SwiftUI
import BookmarkManagerCore

struct MainWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Divider()
            HStack(spacing: 0) {
                FolderTree().frame(width: 272)
                Divider()
                Group {
                    if model.isSearching { SearchResults() }
                    else if model.currentFolder != nil { FolderDetail(path: model.selectedPath) }
                    else { Text("Choose a tab").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                SearchBar(text: $model.query, focus: model.focusSearch).frame(width: 440)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.sheet = .newBookmark(model.selectedPath) } label: { Label("New bookmark", systemImage: "plus") }
                    .help("Add a bookmark to the directory that is open (⌘N)")
                SettingsLink { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newBookmark(let p): BookmarkEditor(bookmark: nil, path: p)
            case .newSecret(let p): BookmarkEditor(bookmark: nil, path: p, secretOnly: true)
            case .editBookmark(let b): BookmarkEditor(bookmark: b, path: model.library.location(ofBookmark: b.id) ?? model.selectedPath)
            case .newFolder(let p): FolderEditor(folder: nil, path: p)
            case .editFolder(let f): FolderEditor(folder: f, path: model.library.path(toFolder: f.id) ?? model.selectedPath)
            case .newTab: TabNameSheet(tab: nil)
            case .renameTab(let t): TabNameSheet(tab: t)
            case .move(let item): MoveSheet(item: item)
            }
        }
        .alert(item: $model.notice) { n in Alert(title: Text(n.title), message: Text(n.message), dismissButton: .default(Text("OK"))) }
        .onAppear(perform: developmentHooks)
    }

    /// Development only, harmless when unset (for trying screens on a scratch BOOKMARKMANAGER_HOME):
    /// BOOKMARKMANAGER_AUTOSHEET=newBookmark|newSecret|editBookmark|newFolder|editFolder|newTab|move|secret|search:<text>|settings[:tab]
    private func developmentHooks() {
        guard let sheet = ProcessInfo.processInfo.environment["BOOKMARKMANAGER_AUTOSHEET"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let b = model.library.allBookmarks.first { $0.hasSecret } ?? model.library.allBookmarks.first
            let f = model.library.allFolders.first
            switch sheet {
            case "newBookmark": model.sheet = .newBookmark(model.selectedPath)
            case "newSecret": model.sheet = .newSecret(model.selectedPath)
            case "editBookmark": if let b { model.sheet = .editBookmark(b) }
            case "newFolder": model.sheet = .newFolder(model.selectedPath)
            case "editFolder": if let f { model.sheet = .editFolder(f) }
            case "newTab": model.sheet = .newTab
            case "move": if let b { model.sheet = .move(.bookmark(b.id)) }
            case "secret": if let b { model.showSecret(b) }
            default:
                if sheet.hasPrefix("search:") { model.query = String(sheet.dropFirst(7)) }
                if sheet.hasPrefix("settings") {
                    model.settingsTab = sheet.split(separator: ":").dropFirst().first.map(String.init) ?? "general"
                    NSApp.activate(ignoringOtherApps: true)
                    // the Settings scene's own action is not reachable from here on every macOS: show the same view in a plain window
                    let w = NSWindow(contentRect: NSRect(x: 600, y: 300, width: 680, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    w.title = "Bookmark Manager Settings"; w.isReleasedWhenClosed = false
                    w.contentView = NSHostingView(rootView: SettingsView().environmentObject(model).environmentObject(model.icons).preferredColorScheme(model.lookInForce.colorScheme).tint(Theme.accent).font(DS.body))
                    w.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

// MARK: - the search box

/// The Mac's own search field (the magnifier, the ✕ to clear, Esc clears), tied to the model's query.
struct SearchBar: NSViewRepresentable {
    @Binding var text: String
    /// changes when ⌘F is pressed: the field takes the keyboard
    var focus: Int

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.placeholderString = "Search bookmarks by name, address or tag"
        f.delegate = context.coordinator
        f.sendsSearchStringImmediately = true
        f.sendsWholeSearchString = false
        f.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
        f.setAccessibilityLabel("Search bookmarks")
        return f
    }
    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.currentEditor() == nil || text.isEmpty, f.stringValue != text { f.stringValue = text }
        if context.coordinator.lastFocus != focus {
            context.coordinator.lastFocus = focus
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchBar
        var lastFocus = 0
        init(_ p: SearchBar) { parent = p; lastFocus = p.focus }
        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSSearchField else { return }
            let v = f.stringValue
            DispatchQueue.main.async { [self] in if parent.text != v { parent.text = v } }
        }
    }
}

// MARK: - the tabs

struct TabBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var tabToDelete: Folder?

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.library.tabs.enumerated()), id: \.element.id) { i, t in
                        TabButton(tab: t, index: i, count: model.library.tabs.count, askDelete: { tabToDelete = $0 })
                    }
                }
                .padding(.horizontal, 12)
            }
            Button { model.sheet = .newTab } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("New tab (⌘T)").accessibilityLabel("New tab")
                .padding(.trailing, 10)
        }
        .frame(height: 40)
        .background(Theme.sidebarTint?.opacity(0.18) ?? Color.clear)
        .opacity(model.isSearching ? 0.55 : 1)
        .confirmationDialog("Delete the tab “\(tabToDelete?.name ?? "")”?", isPresented: Binding(get: { tabToDelete != nil }, set: { if !$0 { tabToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete tab") { if let t = tabToDelete { model.deleteTab(t.id) }; tabToDelete = nil }
            Button("Cancel", role: .cancel) { tabToDelete = nil }.keyboardShortcut(.defaultAction)
        } message: { Text("It is empty, so nothing else is lost.") }
    }
}

struct TabButton: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let tab: Folder
    let index: Int
    let count: Int
    let askDelete: (Folder) -> Void
    @State private var targeted = false
    @State private var over = false

    private var selected: Bool { model.selectedTabId == tab.id && !model.isSearching }

    var body: some View {
        VStack(spacing: 0) {
            Text(tab.name).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background((targeted ? Theme.accent.opacity(0.18) : over ? DS.hover(scheme) : Color.clear), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            Rectangle().fill(selected ? Theme.accent : Color.clear).frame(height: 2).padding(.horizontal, 10)
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .onTapGesture { model.selectTab(tab.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Tab \(tab.name)")
        .help(tab.isEmpty ? "An empty tab" : "\(tab.bookmarkCount) bookmark\(tab.bookmarkCount == 1 ? "" : "s") · drop a bookmark or directory here to move it into this tab")
        .draggable("tab:\(tab.id.uuidString)") { DragPreview(title: tab.name, icon: "folder") }
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first else { return false }
            if token.hasPrefix("tab:"), let id = UUID(uuidString: String(token.dropFirst(4))) {
                guard id != tab.id else { return false }
                model.moveTab(id, to: index); return true
            }
            return model.drop(token, to: FolderPath(tab: tab.id))
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Rename…") { model.sheet = .renameTab(tab) }
            Button("New directory in this tab…") { model.sheet = .newFolder(FolderPath(tab: tab.id)) }
            Divider()
            Button("Move left") { model.moveTab(tab.id, to: index - 1) }.disabled(index == 0)
            Button("Move right") { model.moveTab(tab.id, to: index + 1) }.disabled(index == count - 1)
            Divider()
            Button("Delete…", role: .destructive) {
                if tab.isEmpty && count > 1 { askDelete(tab) } else { model.deleteTab(tab.id) }   // not empty / the last one: the model explains
            }
        }
    }
}

// MARK: - the folder tree

struct FolderTree: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let tab = model.currentTab {
                        TreeRow(folder: tab, path: FolderPath(tab: tab.id), depth: 0)
                        ForEach(tab.folders) { f in TreeBranch(folder: f, path: FolderPath(tab: tab.id).appending(f.id), depth: 1) }
                    }
                }
                .padding(10)
            }
            Divider()
            HStack(spacing: 8) {
                Button { model.sheet = .newFolder(model.newFolderPath) } label: { Label("New directory", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderless).help("A new directory inside the one that is open, or beside it when the levels don't allow one deeper (⇧⌘N)")
                Spacer()
                Button("Rename tab…") { if let t = model.currentTab { model.sheet = .renameTab(t) } }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .background(Theme.sidebarTint?.opacity(0.18) ?? Color.clear)
    }

}

/// A folder and, below it, its sub-folders.
struct TreeBranch: View {
    let folder: Folder
    let path: FolderPath
    let depth: Int
    var body: some View {
        TreeRow(folder: folder, path: path, depth: depth)
        ForEach(folder.folders) { f in TreeBranch(folder: f, path: path.appending(f.id), depth: depth + 1) }
    }
}

struct TreeRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let folder: Folder
    let path: FolderPath
    let depth: Int
    @State private var targeted = false
    @State private var over = false
    @State private var confirmDelete = false

    private var selected: Bool { model.selectedPath == path && !model.isSearching }
    private var tint: Color? { model.color(folder.colorId).map { $0.rgb.color.opacity(scheme == .dark ? 0.30 : 0.22) } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: depth == 0 ? "rectangle.topthird.inset.filled" : "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name).fontWeight(selected ? .semibold : .regular).lineLimit(1)
                if !folder.description.isEmpty { Text(folder.description).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            Text("\(folder.bookmarks.count)").font(DS.secondary).foregroundStyle(.secondary).monospacedDigit().padding(.top, 1)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .padding(.leading, CGFloat(max(0, depth - 1)) * 18 + (depth > 0 ? 6 : 0))
        .background(background, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).strokeBorder(Theme.accent, lineWidth: targeted ? 2 : (model.highlightId == folder.id ? 2 : 0)))
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .onTapGesture { model.select(path) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .help(folder.description.isEmpty ? folder.name : "\(folder.name) — \(folder.description)")
        .modifier(FolderDrag(folder: folder, isTab: depth == 0))
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first else { return false }
            return model.drop(token, to: path)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open") { model.select(path) }
            if path.depth + 1 <= model.library.maxDepth { Button("New directory inside…") { model.sheet = .newFolder(path) } }
            Button("New bookmark here…") { model.sheet = .newBookmark(path) }
            Button("New secret here…") { model.sheet = .newSecret(path) }
            Divider()
            Button(depth == 0 ? "Rename tab…" : "Edit…") { model.sheet = depth == 0 ? .renameTab(folder) : .editFolder(folder) }
            if depth > 0 { Button("Move to…") { model.sheet = .move(.folder(folder.id)) } }
            Button("Sort by name") { model.sortByName(path) }
            if depth > 0 {
                Divider()
                Button("Delete…", role: .destructive) { if folder.isEmpty { confirmDelete = true } else { model.deleteFolder(folder.id) } }
            }
        }
        .confirmationDialog("Delete the \(Library.levelName(depth)) “\(folder.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteFolder(folder.id) }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text("It is empty, so nothing else is lost.") }
    }

    private var background: Color {
        if selected { return Theme.accent.opacity(scheme == .dark ? 0.28 : 0.16) }
        if targeted { return Theme.accent.opacity(0.12) }
        if let tint { return tint }
        return over ? DS.hover(scheme) : Color.clear
    }
}

/// Directories drag; tabs don't (they move along the tab bar).
struct FolderDrag: ViewModifier {
    let folder: Folder
    let isTab: Bool
    func body(content: Content) -> some View {
        if isTab { content } else { content.draggable(DragItem.folder(folder.id).token) { DragPreview(title: folder.name, icon: "folder") } }
    }
}

// MARK: - a directory's page

struct FolderDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let path: FolderPath

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let f = model.library.folder(at: path) {
                header(f).padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 12)
                if f.isEmpty {
                    emptyState(f)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if !f.folders.isEmpty {
                                SectionLabel(path.depth == 0 ? "Directories" : "Sub-directories", detail: "· \(f.folders.count)")
                                VStack(spacing: 0) {
                                    ForEach(f.folders) { sub in
                                        DropGap(path: path, beforeFolder: sub.id)
                                        SubfolderRow(folder: sub, path: path.appending(sub.id))
                                    }
                                }
                            }
                            if !f.bookmarks.isEmpty {
                                SectionLabel("Bookmarks", detail: "· \(f.bookmarks.count)").padding(.top, f.folders.isEmpty ? 0 : 6)
                                GroupedCard {
                                    ForEach(Array(f.bookmarks.enumerated()), id: \.element.id) { i, b in
                                        if i > 0 { RowDivider(inset: 52) }
                                        BookmarkRow(bookmark: b, path: path)
                                    }
                                }
                            } else if !f.folders.isEmpty {
                                Text("No bookmarks at this level — they are in the \(path.depth == 0 ? "directories" : "sub-directories") above.").font(DS.secondary).foregroundStyle(.secondary).padding(.top, 4)
                            }
                            EndDrop(path: path)
                            Text("Click a name to open it in \(browserName). Drag a row onto a directory or a tab to move it; right-click for more.")
                                .font(DS.secondary).foregroundStyle(.tertiary).padding(.top, 8)
                        }
                        .padding(.horizontal, 28).padding(.bottom, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var browserName: String {
        if let id = model.settings.browser, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return Browsers.displayName(u) }
        return Browsers.defaultName() ?? "your browser"
    }

    private func header(_ f: Folder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if !path.isTabRoot { Text(model.library.names(path).dropLast().joined(separator: " › ")).font(DS.secondary).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    if let c = model.color(f.colorId) { Circle().fill(c.rgb.color).frame(width: 12, height: 12).help(c.name).accessibilityLabel("Color code \(c.name)") }
                    Text(f.name).font(DS.title).lineLimit(2)
                }
                if !f.description.isEmpty { Text(f.description).font(DS.secondary).foregroundStyle(.secondary) }
                else { Text(subtitle(f)).font(DS.secondary).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Sort by name") { model.sortByName(path) }.disabled(f.folders.count + f.bookmarks.count < 2).help("Sort the sub-directories and bookmarks here by name, once")
            if path.depth + 1 <= model.library.maxDepth {
                Button { model.sheet = .newFolder(path) } label: { Label("New directory", systemImage: "folder.badge.plus") }
            }
            Button(path.isTabRoot ? "Rename tab…" : "Edit…") { model.sheet = path.isTabRoot ? .renameTab(f) : .editFolder(f) }
            Button { model.sheet = .newBookmark(path) } label: { Label("New bookmark", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private func subtitle(_ f: Folder) -> String {
        let d = f.folders.count, b = f.bookmarks.count, all = f.bookmarkCount
        var parts: [String] = []
        if d > 0 { parts.append("\(d) \(path.depth == 0 ? "director" : "sub-director")\(d == 1 ? "y" : "ies")") }
        parts.append("\(b) bookmark\(b == 1 ? "" : "s")" + (all > b ? " here, \(all) in all" : ""))
        return parts.joined(separator: " · ")
    }

    private func emptyState(_ f: Folder) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder").font(.system(size: 36, weight: .regular)).foregroundStyle(Theme.accent)
            Text(path.isTabRoot ? "This tab is empty" : "This \(Library.levelName(path.depth)) is empty").font(DS.heading)
            Text("Add a bookmark, make a directory to organize them, or drag bookmarks here from another directory or tab.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button { model.sheet = .newBookmark(path) } label: { Label("New bookmark", systemImage: "plus") }.buttonStyle(.borderedProminent)
                if path.depth + 1 <= model.library.maxDepth { Button { model.sheet = .newFolder(path) } label: { Label("New directory", systemImage: "folder.badge.plus") } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

/// A sub-directory on the page: click to open it; drop a bookmark or directory on it to move it inside.
struct SubfolderRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let folder: Folder
    let path: FolderPath
    @State private var targeted = false
    @State private var over = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "folder", color: model.color(folder.colorId)?.rgb.color ?? .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name).fontWeight(.semibold).lineLimit(1)
                if !folder.description.isEmpty { Text(folder.description).font(DS.secondary).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Text(count).font(DS.secondary).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(background, in: RoundedRectangle(cornerRadius: DS.radius))
        .overlay(RoundedRectangle(cornerRadius: DS.radius).strokeBorder(targeted || model.highlightId == folder.id ? Theme.accent : DS.edge(scheme), lineWidth: targeted || model.highlightId == folder.id ? 2 : 1))
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .onTapGesture { model.select(path) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help("Open “\(folder.name)” · drop a bookmark or directory here to move it in")
        .draggable(DragItem.folder(folder.id).token) { DragPreview(title: folder.name, icon: "folder") }
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first else { return false }
            return model.drop(token, to: path)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open") { model.select(path) }
            Button("Edit…") { model.sheet = .editFolder(folder) }
            Button("Move to…") { model.sheet = .move(.folder(folder.id)) }
            Divider()
            Button("Delete…", role: .destructive) { if folder.isEmpty { confirmDelete = true } else { model.deleteFolder(folder.id) } }
        }
        .confirmationDialog("Delete the \(Library.levelName(path.depth)) “\(folder.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteFolder(folder.id) }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text("It is empty, so nothing else is lost.") }
    }

    private var count: String {
        let n = folder.bookmarkCount, d = folder.folders.count
        var s = "\(n) bookmark\(n == 1 ? "" : "s")"
        if d > 0 { s += " · \(d) sub-director\(d == 1 ? "y" : "ies")" }
        return s
    }
    private var background: Color {
        if targeted { return Theme.accent.opacity(0.12) }
        if let c = model.color(folder.colorId) { return c.rgb.color.opacity(scheme == .dark ? 0.26 : 0.18) }
        return over ? DS.hover(scheme) : DS.surface(scheme)
    }
}

/// A bookmark: its site icon, its name (click opens it), its description under, the Secret button, a pencil
/// while the pointer is over it. Tinted with its color code. Drag it; drop another on it to put that one before it.
struct BookmarkRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let bookmark: Bookmark
    let path: FolderPath
    /// in search results: the row shows where it is instead of its description
    var place: String? = nil
    @State private var over = false
    @State private var nameOver = false
    @State private var targeted = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if bookmark.isSecretOnly { IconTile(systemName: "key.fill", color: DS.key).accessibilityHidden(true) }
            else { SiteIcon(address: bookmark.url) }
            VStack(alignment: .leading, spacing: 2) {
                if bookmark.isSecretOnly {
                    // nothing to open: the name is plain text, the Secrets-Only button is the thing to click
                    Text(bookmark.name).fontWeight(.semibold).lineLimit(1)
                } else {
                    Text(bookmark.name).fontWeight(.semibold).lineLimit(1)
                        .foregroundStyle(nameOver ? Theme.accent : Color.primary)
                        .underline(nameOver)
                        .contentShape(Rectangle())
                        .onHover { nameOver = $0 }
                        .onTapGesture { model.open(bookmark) }
                        .help("Open \(bookmark.link?.absoluteString ?? bookmark.url)")
                        .accessibilityAddTraits(.isLink)
                        .accessibilityHint("Opens it in the browser")
                }
                if let place { Text(place).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1) }
                else if !bookmark.description.isEmpty { Text(bookmark.description).font(DS.secondary).foregroundStyle(.secondary).lineLimit(2) }
                else if bookmark.isSecretOnly { Text("Secret only — no address").font(DS.secondary).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if bookmark.hasSecret {
                Button { model.showSecret(bookmark) } label: { Label(bookmark.secretButtonTitle, systemImage: "key.fill").font(DS.secondary) }
                    .buttonStyle(.bordered).controlSize(.small).help("Show the secret in its own window")
            }
            Button { model.sheet = .editBookmark(bookmark) } label: { Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.bordered).controlSize(.small).help("Edit this bookmark").accessibilityLabel("Edit \(bookmark.name)")
                .opacity(over ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(background)
        .overlay(alignment: .top) { if targeted { Rectangle().fill(Theme.accent).frame(height: 3) } }
        .overlay { if model.highlightId == bookmark.id { RoundedRectangle(cornerRadius: DS.radiusSmall).strokeBorder(Theme.accent, lineWidth: 2) } }
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .accessibilityElement(children: .contain)
        .draggable(DragItem.bookmark(bookmark.id).token) { DragPreview(title: bookmark.name, icon: "bookmark") }
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first else { return false }
            // a bookmark lands before this one; a directory dropped on a bookmark goes into this directory
            if case .bookmark = DragItem(token: token) { return model.drop(token, to: path, before: bookmark.id) }
            return model.drop(token, to: path)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            if !bookmark.isSecretOnly {
                Button("Open") { model.open(bookmark) }
                Button("Copy address") { model.copyAddress(bookmark) }
            }
            if bookmark.hasSecret { Button("Show secret") { model.showSecret(bookmark) } }
            Divider()
            Button("Edit…") { model.sheet = .editBookmark(bookmark) }
            Button("Move to…") { model.sheet = .move(.bookmark(bookmark.id)) }
            Divider()
            Button("Delete…", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete the bookmark “\(bookmark.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteBookmark(bookmark.id) }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text(bookmark.hasSecret ? "Its secret goes with it." : "This can't be undone.") }
    }

    private var background: Color {
        if let c = model.color(bookmark.colorId) { return c.rgb.color.opacity(scheme == .dark ? 0.26 : 0.18) }
        return over ? DS.hover(scheme) : Color.clear
    }
}

/// The site's icon, or the link glyph until (or unless) one is found.
struct SiteIcon: View {
    @EnvironmentObject var icons: IconCache
    let address: String
    var size: CGFloat = 28
    /// off in the editor: a half-typed address must not be looked up
    var fetch = true
    var body: some View {
        if let img = icons.image(for: address, fetch: fetch) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size - 6, height: size - 6)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).strokeBorder(Color.black.opacity(0.08)))
                .accessibilityHidden(true)
        } else {
            IconTile(systemName: "link", color: .secondary, size: size).accessibilityHidden(true)
        }
    }
}

// MARK: - drag and drop helpers

/// The thin space above a sub-directory row: a directory dropped there lands just before it.
struct DropGap: View {
    @EnvironmentObject var model: AppModel
    let path: FolderPath
    let beforeFolder: UUID?
    @State private var targeted = false
    var body: some View {
        ZStack {
            Color.clear
            if targeted { Capsule().fill(Theme.accent).frame(height: 3) }
        }
        .frame(height: targeted ? 14 : 6)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first, let item = DragItem(token: token) else { return false }
            if case .folder = item { return model.move(item, to: path, before: beforeFolder) }
            return model.move(item, to: path)
        } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { targeted = t } }
    }
}

/// The space under the last row: a drop there puts the item at the end of this directory.
struct EndDrop: View {
    @EnvironmentObject var model: AppModel
    let path: FolderPath
    @State private var targeted = false
    var body: some View {
        ZStack {
            Color.clear
            if targeted { Text("Put it here, at the end").font(DS.secondary).foregroundStyle(Theme.accent) }
        }
        .frame(height: targeted ? 32 : 14)
        .frame(maxWidth: .infinity)
        .background(targeted ? Theme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first else { return false }
            return model.drop(token, to: path)
        } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { targeted = t } }
    }
}

/// What follows the pointer while something is dragged.
struct DragPreview: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon).font(DS.body).fontWeight(.semibold)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

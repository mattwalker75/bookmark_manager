// The one object the windows watch: the library (tabs, directories, bookmarks, color codes), what is selected,
// the search, the sheets, the settings. It owns library.json (through LibraryStore), opens bookmarks in the chosen
// browser, fetches site icons, and turns every refusal from the core into a plain notice.
import SwiftUI
import BookmarkManagerCore
import Combine

enum MainSheet: Identifiable {
    case newBookmark(FolderPath)
    case editBookmark(Bookmark)
    case newFolder(FolderPath)
    case editFolder(Folder)
    case newTab
    case renameTab(Folder)
    /// Move to…: choose where a bookmark or directory goes
    case move(DragItem)
    var id: String {
        switch self {
        case .newBookmark(let p): return "newBookmark-\(p)"
        case .editBookmark(let b): return "editBookmark-\(b.id)"
        case .newFolder(let p): return "newFolder-\(p)"
        case .editFolder(let f): return "editFolder-\(f.id)"
        case .newTab: return "newTab"
        case .renameTab(let t): return "renameTab-\(t.id)"
        case .move(let i): return "move-\(i.token)"
        }
    }
}

struct Notice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library: Library
    @Published var selectedTabId: UUID
    /// the folder whose contents the window shows (inside the selected tab)
    @Published var selectedPath: FolderPath
    @Published var query = ""
    @Published var sheet: MainSheet?
    @Published var notice: Notice?
    /// a row to flash after "Show in place"
    @Published var highlightId: UUID?
    /// bump to put the keyboard in the search box (⌘F)
    @Published var focusSearch = 0
    @Published var settings = AppSettings.load() { didSet { guard settings != oldValue else { return }; settings.save(); Theme.apply(settings); icons.enabled = settings.fetchIcons } }
    @Published var settingsTab = "general"
    @Published var previewLook: Appearance?
    var lookInForce: Appearance { previewLook ?? settings.effectiveAppearance }

    let store: LibraryStore
    /// the site icons; views that show one observe it directly (SiteIcon), so an arriving icon redraws only them
    let icons: IconCache
    /// the library (or its secrets) could not be read at launch: no sample data, and the notice says what was kept
    private(set) var loadTrouble = false

    init() {
        store = LibraryStore()
        icons = IconCache(folder: store.folder.appendingPathComponent("icons", isDirectory: true))
        var lib = Library.fresh()
        var first: Notice?
        do { lib = try store.load() } catch let e as BMError { loadTrouble = true; first = Notice(title: "The bookmarks could not be read", message: e.message) } catch { loadTrouble = true }
        if let p = store.problem { loadTrouble = true; first = Notice(title: "The secrets could not be read", message: p) }
        library = lib
        selectedTabId = lib.tabs[0].id
        selectedPath = FolderPath(tab: lib.tabs[0].id)
        notice = first
        Theme.apply(settings)
        icons.enabled = settings.fetchIcons
    }

    // MARK: reading

    var currentTab: Folder? { library.tab(selectedTabId) }
    var currentFolder: Folder? { library.folder(at: selectedPath) }
    var isSearching: Bool { !Library.words(query).isEmpty }
    var hits: [SearchHit] { library.search(query) }
    func color(_ id: UUID?) -> ColorCode? { library.color(id) }
    /// "Work › Self-hosted apps"
    func placeName(_ path: FolderPath) -> String { library.names(path).joined(separator: " › ") }
    /// Where a new directory goes: inside the open one when the levels allow it, else beside it (up the path).
    var newFolderPath: FolderPath {
        var p = selectedPath
        while p.depth + 1 > library.maxDepth, let parent = p.parent { p = parent }
        return p
    }

    // MARK: selection

    func selectTab(_ id: UUID) {
        guard library.tab(id) != nil else { return }
        selectedTabId = id
        selectedPath = FolderPath(tab: id)
    }

    func select(_ path: FolderPath) {
        guard library.folder(at: path) != nil else { return }
        selectedTabId = path.tabId
        selectedPath = path
    }

    /// After a change, the selection still points at something that exists.
    private func fixSelection() {
        if library.tab(selectedTabId) == nil { selectedTabId = library.tabs[0].id; selectedPath = FolderPath(tab: selectedTabId); return }
        var p = selectedPath
        while library.folder(at: p) == nil, let parent = p.parent { p = parent }
        if library.folder(at: p) == nil { p = FolderPath(tab: selectedTabId) }
        if p != selectedPath { selectedPath = p }
    }

    /// Jump to a search hit: its tab, the directory holding it, and a flash on its row.
    func showInPlace(_ hit: SearchHit) {
        query = ""
        select(hit.isFolder ? (hit.path.parent ?? hit.path) : hit.path)
        flash(hit.id)
    }

    func flash(_ id: UUID) {
        highlightId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.highlightId == id { self?.highlightId = nil } }
    }

    // MARK: saving

    /// Saves; false (with a notice) when it could not be written — the caller puts the old library back, so what
    /// the window shows is always what the disk holds.
    private func save() -> Bool {
        do { try store.save(library) } catch { notice = Notice(title: "The bookmarks could not be saved", message: (error as? BMError)?.message ?? error.localizedDescription); return false }
        fixSelection()
        return true
    }

    /// Runs a change on the library; a refusal (or a failed save) becomes a notice and nothing changes. True when it went through.
    @discardableResult
    func change(_ title: String = "That can't be done", _ work: (inout Library) throws -> Void) -> Bool {
        var lib = library
        do { try work(&lib) } catch { notice = Notice(title: title, message: (error as? BMError)?.message ?? error.localizedDescription); return false }
        guard lib != library else { return true }
        let old = library
        library = lib
        if !save() { library = old; fixSelection(); return false }
        return true
    }

    /// What a change would say if it were refused, without doing it (for panes that show the reason in place).
    func reason(_ work: (inout Library) throws -> Void) -> String? {
        var lib = library
        do { try work(&lib); return nil } catch { return (error as? BMError)?.message ?? error.localizedDescription }
    }

    // MARK: tabs

    func addTab(_ name: String) {
        var newId: UUID?
        if change("The tab wasn't made", { newId = try $0.addTab(name) }), let id = newId { selectTab(id) }
    }
    func renameTab(_ id: UUID, _ name: String) { change("The tab wasn't renamed") { try $0.renameTab(id, name) } }
    func deleteTab(_ id: UUID) { change("The tab wasn't deleted") { try $0.deleteTab(id) } }
    func moveTab(_ id: UUID, to index: Int) { change { $0.moveTab(id, to: index) } }

    // MARK: directories

    func addFolder(name: String, description: String, colorId: UUID?, in path: FolderPath) {
        change("The directory wasn't made") { _ = try $0.addFolder(name: name, description: description, colorId: colorId, in: path) }
    }
    func updateFolder(_ id: UUID, name: String, description: String, colorId: UUID?) {
        change("The directory wasn't saved") { try $0.updateFolder(id, name: name, description: description, colorId: colorId) }
    }
    func deleteFolder(_ id: UUID) { change("The directory wasn't deleted") { try $0.deleteFolder(id) } }
    func sortByName(_ path: FolderPath) { change { $0.sortByName(at: path) } }

    // MARK: bookmarks

    func addBookmark(_ b: Bookmark, in path: FolderPath) {
        if change("The bookmark wasn't added", { try $0.addBookmark(b, in: path) }) { icons.warm(b.url) }
    }
    func updateBookmark(_ b: Bookmark) {
        if change("The bookmark wasn't saved", { try $0.updateBookmark(b) }) { icons.warm(b.url); SecretWindows.refresh(b) }
    }
    func deleteBookmark(_ id: UUID) {
        SecretWindows.close(id)
        change { $0.deleteBookmark(id) }
    }

    /// A drop (or Move to…). False = nothing changed (the reason was shown).
    @discardableResult
    func move(_ item: DragItem, to dest: FolderPath, before: UUID? = nil) -> Bool {
        change("It wasn't moved") { try $0.move(item, to: dest, before: before) }
    }
    func drop(_ token: String, to dest: FolderPath, before: UUID? = nil) -> Bool {
        if token.hasPrefix("tab:") { return false }
        guard let item = DragItem(token: token) else { return false }
        // let go where the drag began (a directory on its own row): nothing happens, no alert
        if case .folder(let id) = item, library.path(toFolder: id) == dest { return false }
        return move(item, to: dest, before: before)
    }
    func canDrop(_ token: String, to dest: FolderPath) -> Bool {
        guard let item = DragItem(token: token) else { return false }
        return library.canMove(item, to: dest)
    }

    // MARK: opening

    /// Opens the bookmark in the chosen browser (Settings → General), or the Mac's default one.
    func open(_ b: Bookmark) {
        guard let url = b.link else { notice = Notice(title: "“\(b.name)” can't be opened", message: "Its address “\(b.url)” isn't one a browser can open. Edit the bookmark and check the address."); return }
        Browsers.open(url, with: settings.browser) { [weak self] problem in self?.notice = Notice(title: "“\(b.name)” didn't open", message: problem) }
    }

    func copyAddress(_ b: Bookmark) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(b.link?.absoluteString ?? b.url, forType: .string)
    }

    func showSecret(_ b: Bookmark) { SecretWindows.show(b, model: self) }

    // MARK: settings that live in the library

    func setMaxDepth(_ d: Int) { change("The directory levels weren't changed") { try $0.setMaxDepth(d) } }
    func addColor(name: String, rgb: RGB) { change("The color wasn't added") { _ = try $0.addColor(name: name, rgb: rgb) } }
    func updateColor(_ id: UUID, name: String? = nil, rgb: RGB? = nil) {
        change("The color wasn't changed") { lib in
            if let name { try lib.renameColor(id, name) }
            if let rgb { lib.recolor(id, rgb) }
        }
    }
    func removeColor(_ id: UUID) { change { $0.removeColor(id) } }

    // MARK: export and import

    func exportData(includeSecrets: Bool) throws -> Data { try Transfer.export(library, includeSecrets: includeSecrets) }

    func importFile(_ f: ExportFile, mode: ImportMode) -> [String] {
        let (lib, notes) = Transfer.apply(f, to: library, mode: mode)
        let old = library
        library = lib
        guard save() else { library = old; fixSelection(); return [] }
        // open secret windows: closed for bookmarks that are gone, brought up to date for the rest (a replace keeps ids)
        let stillThere = Set(lib.allBookmarks.map(\.id))
        for id in old.allBookmarks.map(\.id) where !stillThere.contains(id) { SecretWindows.close(id) }
        for b in lib.allBookmarks { SecretWindows.refresh(b) }
        if mode == .replace { selectTab(library.tabs[0].id) }
        // icons are fetched as rows come into view — not all at once here
        return notes
    }

    // MARK: development hooks (harmless when unset)

    /// BOOKMARKMANAGER_SAMPLE=1 with an empty BOOKMARKMANAGER_HOME fills in example bookmarks (for screenshots)
    func addSampleIfAsked() {
        guard !loadTrouble, ProcessInfo.processInfo.environment["BOOKMARKMANAGER_SAMPLE"] == "1", library.allBookmarks.isEmpty, library.tabs.count == 1 else { return }
        library = Sample.library()
        selectTab(library.tabs[0].id)
        _ = save()
    }
}

enum Appearance: String, Codable, CaseIterable {
    case system, light, dark
    var label: String { switch self { case .system: return "Follow the system"; case .light: return "Light"; case .dark: return "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

/// The app's own settings, saved as settings.json beside library.json. (Directory levels and the color codes
/// live in the library itself, so an export carries them.)
struct AppSettings: Codable, Equatable {
    var appearance: Appearance = .system
    var accent: ThemeColor = .blue
    var themes: [CustomTheme] = []
    var activeThemeId: UUID?
    /// the bundle id of the browser bookmarks open in; nil = the Mac's default browser
    var browser: String?
    var fetchIcons = true

    var activeTheme: CustomTheme? { activeThemeId.flatMap { id in themes.first { $0.id == id } } }
    var effectiveAppearance: Appearance { activeTheme?.look ?? appearance }

    init() {}
    // every field optional on disk, so a settings file from an older version still loads
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        accent = try c.decodeIfPresent(ThemeColor.self, forKey: .accent) ?? .blue
        themes = try c.decodeIfPresent([CustomTheme].self, forKey: .themes) ?? []
        activeThemeId = try c.decodeIfPresent(UUID.self, forKey: .activeThemeId)
        browser = try c.decodeIfPresent(String.self, forKey: .browser)
        fetchIcons = try c.decodeIfPresent(Bool.self, forKey: .fetchIcons) ?? true
    }

    static var url: URL { Home.folder().appendingPathComponent("settings.json") }
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }
    func save() { if let data = try? JSONEncoder().encode(self) { try? data.write(to: AppSettings.url, options: .atomic) } }
}

// The one object the windows watch: the library (tabs, directories, bookmarks, color codes), what is selected,
// the search, the sheets, the settings. It owns library.json (through LibraryStore), opens bookmarks in the chosen
// browser, fetches site icons, and turns every refusal from the core into a plain notice.
import SwiftUI
import BookmarkManagerCore
import Combine
import CryptoKit

enum MainSheet: Identifiable {
    case newBookmark(FolderPath)
    /// the same editor with "Secret only" already picked
    case newSecret(FolderPath)
    case editBookmark(Bookmark)
    case newFolder(FolderPath)
    case editFolder(Folder)
    case newTab
    case renameTab(Folder)
    /// Move to…: choose where a bookmark or directory goes
    case move(DragItem)
    /// the link check: its progress, then its problems
    case linkReport
    var id: String {
        switch self {
        case .linkReport: return "linkReport"
        case .newBookmark(let p): return "newBookmark-\(p)"
        case .newSecret(let p): return "newSecret-\(p)"
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
    @Published var query = "" { didSet { if query != oldValue { focusId = nil } } }
    /// the row the arrow keys are on: a sub-directory or bookmark of the open directory, or a search hit (Matt, Oct 29 2026)
    @Published var focusId: UUID?
    @Published var sheet: MainSheet?
    @Published var notice: Notice?
    /// a row to flash after "Show in place"
    @Published var highlightId: UUID?
    /// bump to put the keyboard in the search box (⌘F)
    @Published var focusSearch = 0
    @Published var settings = AppSettings.load() { didSet { guard settings != oldValue else { return }; settings.save(); Theme.apply(settings); icons.enabled = settings.fetchIcons } }
    @Published var settingsTab = "general"
    /// the last link check's outcome (kept on disk), and the one running now
    @Published var linkReport: LinkReport?
    @Published var linkProgress: LinkCheckProgress?
    private var linkTask: Task<Void, Never>?
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
        // directories that no longer exist drop out of the remembered tree state
        let known = Set(lib.allFolders.map(\.id))
        if !settings.expanded.isSubset(of: known) { settings.expanded.formIntersection(known) }
        linkReport = LinkReport.load(from: store.folder)
        // the daily backup also comes while the app stays open for days (review 2): looked at once an hour
        if !Home.isTesting {
            backupTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.backupAtLaunchIfDue() }
            }
        }
    }
    private var backupTimer: Timer?
    deinit { backupTimer?.invalidate() }

    // MARK: checking links (Matt, Oct 29 2026)

    /// The marks the rows wear: the last check's problems, for bookmarks whose address hasn't changed since.
    var linkProblems: [UUID: LinkResult] {
        guard let r = linkReport else { return [:] }
        var out: [UUID: LinkResult] = [:]
        for p in r.problems { if let b = library.bookmark(p.bookmarkId), b.url == p.url { out[b.id] = p } }
        return out
    }
    var linkCheckRunning: Bool { linkProgress != nil }
    /// The banner above the list: an automatic check found problems and nobody has looked yet.
    var linkBanner: LinkReport? { guard let r = linkReport, r.automatic, !r.bannerDismissed, !linkProblems.isEmpty else { return nil }; return r }
    /// Whether the schedule says a check is due now.
    func linkCheckDue(now: Date = Date()) -> Bool {
        guard settings.linkCheckDays > 0 else { return false }
        guard let last = linkReport?.checkedAt else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(settings.linkCheckDays) * 86_400
    }

    /// Checks every address (or one directory's). `automatic` = run by the schedule: no sheet, a banner instead.
    /// `inMainWindow` = false when Settings shows the sheet itself.
    func checkLinks(in path: FolderPath? = nil, automatic: Bool = false, inMainWindow: Bool = true) {
        guard linkTask == nil else { if !automatic, inMainWindow { sheet = .linkReport }; return }
        let bookmarks = path.flatMap { library.folder(at: $0) }?.allBookmarks ?? library.allBookmarks
        let items = bookmarks.compactMap { b in b.link.map { (id: b.id, url: $0) } }.filter { ["http", "https"].contains($0.url.scheme ?? "") }
        let scope = path.map { placeName($0) }
        linkProgress = LinkCheckProgress(total: items.count)
        if !automatic, inMainWindow { sheet = .linkReport }
        let started = Date()
        linkTask = Task { [weak self] in
            let found = await LinkChecker.check(items) { [weak self] n in self?.linkProgress?.done = n }
            guard let self else { return }
            let cancelled = Task.isCancelled
            var report = LinkReport(checkedAt: Date(), checked: found.count, problems: found.filter(\.verdict.isProblem), scope: scope, automatic: automatic, seconds: Date().timeIntervalSince(started))
            if scope != nil, let old = linkReport {
                // one directory checked: the other directories' marks stay as they were, and count as checked
                // (review 2: otherwise the summary could read "5 of 2 addresses")
                let ids = Set(items.map(\.id))
                let elsewhere = old.problems.filter { !ids.contains($0.bookmarkId) }
                report.problems += elsewhere
                report.checked += elsewhere.count
                report.scope = nil
            }
            if !cancelled || !found.isEmpty { linkReport = report; report.save(in: store.folder) }
            linkProgress = nil
            linkTask = nil
        }
    }
    func cancelLinkCheck() { linkTask?.cancel() }
    func dismissLinkBanner() { linkReport?.bannerDismissed = true; linkReport?.save(in: store.folder) }
    /// "Use new address" on a moved bookmark.
    func useNewAddress(_ r: LinkResult) {
        guard case .moved(let to) = r.verdict, var b = library.bookmark(r.bookmarkId) else { return }
        b.url = to
        updateBookmark(b)
        linkReport?.problems.removeAll { $0.bookmarkId == r.bookmarkId }
        linkReport?.save(in: store.folder)
    }
    /// Show in place from the link sheet: the bookmark's directory, with its row marked.
    func reveal(bookmark id: UUID) {
        guard let p = library.location(ofBookmark: id) else { return }
        query = ""; select(p); flash(id)
    }
    /// The schedule: a quiet check a few seconds after launch when one is due.
    func runScheduledLinkCheckIfDue() {
        guard linkCheckDue() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, linkCheckDue() else { return }
            checkLinks(automatic: true)
        }
    }

    // MARK: the folder tree's open and closed branches (Matt, Oct 29 2026: chevrons, remembered)

    func isExpanded(_ folderId: UUID) -> Bool { settings.expanded.contains(folderId) }
    func setExpanded(_ folderId: UUID, _ open: Bool) {
        if open { settings.expanded.insert(folderId) } else { settings.expanded.remove(folderId) }
    }
    func toggleExpanded(_ folderId: UUID) { setExpanded(folderId, !isExpanded(folderId)) }
    /// Opens every directory above `path`, so its row can be seen (the directory itself stays as it was).
    func reveal(_ path: FolderPath) {
        let above = path.ids.dropFirst().dropLast()
        guard !above.isEmpty, !above.allSatisfy(settings.expanded.contains) else { return }
        settings.expanded.formUnion(above)
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
        focusId = nil
    }

    func select(_ path: FolderPath) {
        guard library.folder(at: path) != nil else { return }
        selectedTabId = path.tabId
        selectedPath = path
        focusId = nil
        reveal(path)
    }

    // MARK: the keyboard (Matt, Oct 29 2026): arrows walk the rows, Return opens, Space shows the secret

    /// The ids the arrow keys move through, top to bottom, exactly as the page shows them: the open directory's
    /// sub-directories then its bookmarks — or, while searching, the hits grouped by tab.
    var keyboardRows: [UUID] {
        if isSearching { let all = hits; return library.tabs.flatMap { t in all.filter { $0.tabId == t.id }.map(\.id) } }
        guard let f = currentFolder else { return [] }
        return f.folders.map(\.id) + f.bookmarks.map(\.id)
    }
    /// ↓ is +1, ↑ is −1; from nowhere, ↓ starts at the top and ↑ at the bottom. Stops at the ends.
    func moveFocus(_ delta: Int) {
        let rows = keyboardRows
        guard !rows.isEmpty else { focusId = nil; return }
        guard let cur = focusId, let i = rows.firstIndex(of: cur) else { focusId = delta >= 0 ? rows.first : rows.last; return }
        focusId = rows[min(max(i + delta, 0), rows.count - 1)]
    }
    /// the focused row's bookmark, if it is one
    var focusedBookmark: Bookmark? { focusId.flatMap { library.bookmark($0) } }
    /// Return: a bookmark opens (a secret-only one shows its secret), a directory is opened on the page.
    func activateFocus() {
        guard let id = focusId else { return }
        if isSearching {
            guard let hit = hits.first(where: { $0.id == id }) else { return }
            if case .bookmark(let b) = hit.kind { open(b) } else { query = ""; select(hit.path) }
            return
        }
        if let b = library.bookmark(id) { open(b) }
        else if let p = library.path(toFolder: id), p.parent == selectedPath { select(p) }
    }
    /// Space: the focused bookmark's secret, when it has one.
    func showFocusedSecret() { if let b = focusedBookmark, b.hasSecret { showSecret(b) } }
    /// ⌘L: the focused bookmark's address (a secret-only one has none).
    func copyFocusedAddress() { if let b = focusedBookmark, !b.isSecretOnly { copyAddress(b) } }
    /// ⌘↑: the directory above, with the one just left under the arrow keys.
    func goUp() {
        guard !isSearching, let parent = selectedPath.parent else { return }
        let from = selectedPath.folderId
        select(parent)
        focusId = from
    }
    func selectTab(number n: Int) { if n >= 1, n <= library.tabs.count { selectTab(library.tabs[n - 1].id) } }
    func selectNextTab(_ step: Int) {
        guard let i = library.tabs.firstIndex(where: { $0.id == selectedTabId }) else { return }
        let n = library.tabs.count
        selectTab(library.tabs[((i + step) % n + n) % n].id)
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
        if hit.isFolder, let parent = hit.path.parent, !parent.isTabRoot { setExpanded(parent.folderId, true) }   // the found directory's row is in view
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
        backupAfterChangeIfDue()
        return true
    }

    // MARK: backups (Matt, Oct 29 2026)

    var backupStore: BackupStore {
        BackupStore(folder: settings.backupFolder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? store.folder.appendingPathComponent("Backups", isDirectory: true))
    }
    /// the backups in the folder, as the pane shows them (refreshBackups() reads the folder again)
    @Published var backups: [BackupEntry] = []
    func refreshBackups() { backups = backupStore.list() }

    /// Writes a backup now. `force` = even when nothing changed since the last one (by hand, before a restore).
    /// Returns a sentence about what happened, or nil when it was skipped because nothing changed.
    @discardableResult
    func backUp(reason: BackupReason, force: Bool = false, kept: Bool = false, note: String = "") -> String? {
        // a launch that lost its secrets or its library must not push good backups out of the rotation (review 2)
        if loadTrouble, !force { return nil }
        let digest = Backup.digest(library)
        if !force, digest == settings.lastBackupDigest { return nil }
        do {
            let key = try store.secrets.currentKey() ?? (library.allBookmarks.contains(where: \.hasSecret) ? try store.secrets.ensureKey() : nil)
            // a passphrase set before this Mac's key was replaced would open nothing: left out, and the pane says so
            let wrap = settings.backupPassphrase.flatMap { w in key.map { w.matches($0) } == false ? nil : w }
            let data = try Backup.make(library, key: key, passphrase: wrap, reason: reason, kept: kept, note: note, secretsInClear: settings.backupSecretsPlain)
            let url = try backupStore.write(data, at: Date())
            settings.lastBackupDigest = digest; settings.lastBackupAt = Date()
            backupStore.prune(keep: settings.backupKeep)
            refreshBackups()
            var said = "Backed up to \(url.lastPathComponent)."
            if loadTrouble { said += " This launch loaded without its secrets (or its bookmarks), so this backup holds what you see now, no more." }
            return said
        } catch {
            let why = (error as? BMError)?.message ?? error.localizedDescription
            notice = Notice(title: "The backup could not be written", message: why)
            return why
        }
    }
    private var backupIsDue: Bool {
        guard let last = settings.lastBackupAt else { return true }
        return Date().timeIntervalSince(last) >= 86_400
    }
    /// At launch: a daily backup when the last one is a day old (and something changed).
    func backupAtLaunchIfDue() {
        guard settings.backupsEnabled, [.daily, .dailyAndQuit].contains(settings.backupWhen), backupIsDue else { return }
        backUp(reason: .daily)
    }
    private var lastBackupTry: Date?
    /// After a save: the "after every change" setting, at most once an hour — tried or not (a folder that can't be
    /// written is complained about once an hour, not on every change).
    private func backupAfterChangeIfDue() {
        guard settings.backupsEnabled, settings.backupWhen == .everyChange else { return }
        if let last = settings.lastBackupAt, Date().timeIntervalSince(last) < 3_600 { return }
        if let tried = lastBackupTry, Date().timeIntervalSince(tried) < 3_600 { return }
        lastBackupTry = Date()
        backUp(reason: .change)
    }
    /// When the app quits: the "and when the app quits" setting, if something changed. Returns the problem when
    /// the backup could not be written, so the quit can be held up and the person told.
    @discardableResult
    func backupOnQuit() -> String? {
        guard settings.backupsEnabled, settings.backupWhen == .dailyAndQuit else { return nil }
        guard let said = backUp(reason: .quit), !said.hasPrefix("Backed up") else { return nil }
        return said
    }
    /// The passphrase was set for a key this Mac no longer has (the key was replaced after unreadable secrets).
    var backupPassphraseStale: Bool {
        guard let w = settings.backupPassphrase, let k = try? store.secrets.currentKey() else { return false }
        return !w.matches(k)
    }
    func setKept(_ e: BackupEntry, kept: Bool, note: String) {
        do { try backupStore.setKept(e.url, kept: kept, note: note) } catch { notice = Notice(title: "The backup wasn't marked", message: (error as? BMError)?.message ?? error.localizedDescription) }
        refreshBackups()
    }
    func deleteBackup(_ e: BackupEntry) {
        do { try FileManager.default.removeItem(at: e.url) } catch { notice = Notice(title: "The backup wasn't deleted", message: error.localizedDescription) }
        refreshBackups()
        // nothing left: the next launch or quit writes one again, changed or not
        if !backups.contains(where: \.readable) { settings.lastBackupDigest = nil }
    }
    /// Verify: with this Mac's key, a key file chosen, or a passphrase typed.
    func checkBackup(at url: URL, keyFile: URL? = nil, passphrase: String? = nil) -> Result<BackupCheck, BMError> {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .failure(BMError("Could not read \(url.lastPathComponent): \(error.localizedDescription)")) }
        var key: SymmetricKey?
        var how = "this Mac's key"
        if let keyFile {
            guard let d = try? Data(contentsOf: keyFile), d.count == 32 else { return .failure(BMError("\(keyFile.lastPathComponent) isn't a Bookmark Manager key file.")) }
            key = SymmetricKey(data: d); how = "the key file \(keyFile.lastPathComponent)"
        } else if let passphrase {
            guard let f = try? Backup.read(data), let wrap = f.passphrase else { return .failure(BMError("This backup has no passphrase on it; it needs the key file.")) }
            do { key = try wrap.unwrap(passphrase: passphrase) } catch let e as BMError { return .failure(e) } catch { return .failure(BMError(error.localizedDescription)) }
            how = "the passphrase"
        } else {
            key = try? store.secrets.currentKey()
        }
        let result = Backup.check(data, at: url, key: key, openedWith: how)
        // a key file or passphrase that opened a key, but not the key these secrets were sealed with: say so, not "can't restore"
        if keyFile != nil || passphrase != nil, case .success(let c) = result, c.hasSecrets, !c.secretsReadable {
            return .failure(BMError(passphrase != nil
                ? "The passphrase opened a key, but it isn't the key these secrets were sealed with — the passphrase was set before that Mac's key changed. Use the key file instead."
                : "\(keyFile!.lastPathComponent) isn't the key these secrets were sealed with. Try another copy of secret.key, or the passphrase."))
        }
        return result
    }
    /// Restore: a kept backup of "now" first, then the backup's library (its secrets re-sealed with this Mac's key).
    func restoreBackup(_ check: BackupCheck) -> String {
        guard check.canRestore else { return "This backup can't be restored as it is." }
        // the safety backup is a must, not a wish (review 2): without it nothing is replaced
        if !library.isFresh {
            let said = backUp(reason: .beforeRestore, force: true, kept: true, note: "Before restoring \(check.url.lastPathComponent)")
            guard said?.hasPrefix("Backed up") == true else {
                return "Nothing was restored: the safety backup of what is here now could not be written. \(said ?? "") Fix the backups folder in Settings → Backups and try again."
            }
        }
        let lib = Backup.library(check.file, secrets: check.secrets)
        let before = library
        let notes = importFile(ExportFile(secretsIncluded: true, library: lib), mode: .replace)
        if library == before, lib != before {
            return "Nothing was restored: \(notice?.message ?? "the bookmarks could not be saved.")"
        }
        settings.lastBackupDigest = Backup.digest(library)
        refreshBackups()
        var s = "Restored \(check.file.counts.text) from \(check.url.lastPathComponent)."
        if !notes.isEmpty { s += " " + notes.joined(separator: " ") }
        return s
    }
    /// A copy of secret.key, for the fresh-Mac day.
    func saveKeyCopy(to url: URL) throws {
        let key = try store.secrets.ensureKey()
        try key.withUnsafeBytes { Data($0) }.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func setBackupPassphrase(_ p: String) throws {
        settings.backupPassphrase = try PassphraseWrap.make(key: try store.secrets.ensureKey(), passphrase: p)
        settings.lastBackupDigest = nil   // the next backup carries it
    }
    func clearBackupPassphrase() { settings.backupPassphrase = nil; settings.lastBackupDigest = nil }
    func setBackupSecretsPlain(_ plain: Bool) { guard settings.backupSecretsPlain != plain else { return }; settings.backupSecretsPlain = plain; settings.lastBackupDigest = nil }

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
        if change("The directory wasn't made", { _ = try $0.addFolder(name: name, description: description, colorId: colorId, in: path) }), !path.isTabRoot {
            setExpanded(path.folderId, true)   // the new directory can be seen in the tree
        }
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
        if b.isSecretOnly { showSecret(b); return }   // nothing to open in a browser: "opening" it shows the secret
        guard let url = b.link else { notice = Notice(title: "“\(b.name)” can't be opened", message: "Its address “\(b.url)” isn't one a browser can open. Edit the bookmark and check the address."); return }
        let choice = browserChoice(for: b) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        // said once per bookmark per launch (review 2: it used to say it on every click)
        if let note = choice.note, toldMissingBrowser.insert(b.id).inserted { notice = Notice(title: "“\(b.name)” opened in the browser from Settings", message: note) }
        Browsers.open(url, with: choice.id) { [weak self] problem in self?.notice = Notice(title: "“\(b.name)” didn't open", message: problem) }
    }

    private var toldMissingBrowser = Set<UUID>()

    /// The browser a bookmark opens in: its own when it has one that is installed, else the one from Settings
    /// (with a sentence when its own has gone missing).
    func browserChoice(for b: Bookmark, installed: (String) -> Bool) -> (id: String?, note: String?) {
        guard let own = b.browser else { return (settings.browser, nil) }
        if installed(own) { return (own, nil) }
        return (settings.browser, "The browser picked for this bookmark isn't installed any more, so the browser from Settings was used. Edit the bookmark to pick another, or set it back to the browser from Settings.")
    }

    func copyAddress(_ b: Bookmark) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(b.link?.absoluteString ?? b.url, forType: .string)
    }

    /// Shows the secret window — after Touch ID (or the Mac's password) when Settings asks for it; one check
    /// covers the next minute, so opening three secrets in a row asks once.
    private var gateBusy = false
    func showSecret(_ b: Bookmark) {
        guard settings.touchIDForSecrets, !SecretGate.recentlyPassed, !SecretWindows.isOpen(b.id) else { SecretWindows.show(b, model: self); return }
        guard !gateBusy else { return }   // one prompt at a time (Space twice)
        gateBusy = true
        SecretGate.check(reason: "show the secret for “\(b.name)”") { [weak self] passed, problem in
            guard let self else { return }
            self.gateBusy = false
            if passed { SecretWindows.show(b, model: self) }
            else if let problem { self.notice = Notice(title: "The secret stays hidden", message: problem) }
        }
    }

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
    /// the directories whose sub-directories are shown in the folder tree (everything else is collapsed; remembered)
    var expanded: Set<UUID> = []
    /// a secret window hides itself after this many minutes without being used; 0 = never (Matt, Oct 29 2026)
    var secretHideMinutes = 5
    /// Touch ID (or the Mac's password) before a secret is shown
    var touchIDForSecrets = false
    /// check every address on its own every this many days; 0 = never (Matt, Oct 29 2026)
    var linkCheckDays = 0
    // backups (Matt, Oct 29 2026)
    var backupsEnabled = true
    /// nil = <home>/Backups
    var backupFolder: String?
    var backupWhen = BackupWhen.dailyAndQuit
    var backupKeep = 14
    /// this Mac's key sealed with the passphrase, when one was set (goes into every backup)
    var backupPassphrase: PassphraseWrap?
    /// the secrets go into backups as plain text (Matt, Oct 30 2026); off = sealed with this Mac's key
    var backupSecretsPlain = false
    var lastBackupDigest: String?
    var lastBackupAt: Date?

    var activeTheme: CustomTheme? { activeThemeId.flatMap { id in themes.first { $0.id == id } } }
    var effectiveAppearance: Appearance { activeTheme?.look ?? appearance }

    init() {}
    // every field optional on disk, so a settings file from an older version still loads — and every field forgives
    // its own bad value (review 2: one wrongly typed value used to make the whole file unreadable, which reset everything)
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        func readOptional<T: Decodable>(_ key: CodingKeys) -> T? { try? c.decodeIfPresent(T.self, forKey: key) }
        appearance = read(.appearance, .system)
        accent = read(.accent, .blue)
        themes = read(.themes, [])
        activeThemeId = readOptional(.activeThemeId)
        browser = (readOptional(.browser) as String?).flatMap { $0.isEmpty ? nil : $0 }
        fetchIcons = read(.fetchIcons, true)
        expanded = read(.expanded, [])
        secretHideMinutes = max(0, read(.secretHideMinutes, 5))
        touchIDForSecrets = read(.touchIDForSecrets, false)
        linkCheckDays = max(0, read(.linkCheckDays, 0))
        backupsEnabled = read(.backupsEnabled, true)
        backupFolder = (readOptional(.backupFolder) as String?).flatMap { $0.isEmpty ? nil : $0 }
        backupWhen = read(.backupWhen, .dailyAndQuit)
        backupKeep = max(1, read(.backupKeep, 14))
        backupPassphrase = readOptional(.backupPassphrase)
        backupSecretsPlain = read(.backupSecretsPlain, false)
        lastBackupDigest = readOptional(.lastBackupDigest)
        lastBackupAt = readOptional(.lastBackupAt)
    }

    static var url: URL { Home.folder().appendingPathComponent("settings.json") }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static func load() -> AppSettings {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let s = try? d.decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }
    func save() {
        guard let data = try? AppSettings.encoder.encode(self) else { return }
        try? data.write(to: AppSettings.url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppSettings.url.path)   // it holds the passphrase wrap
    }
}

/// When backups are written on their own.
enum BackupWhen: String, Codable, CaseIterable, Identifiable {
    case daily, dailyAndQuit, everyChange, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Every day"
        case .dailyAndQuit: return "Every day, and when the app quits"
        case .everyChange: return "After every change (at most once an hour)"
        case .manual: return "Only when I click Back up now"
        }
    }
}

extension Bookmark {
    /// The button on the row: "Secret" beside an address, "Secrets-Only" when the item is nothing but a secret (Matt's wording).
    var secretButtonTitle: String { isSecretOnly ? "Secrets-Only" : "Secret" }
}

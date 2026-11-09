// Import from a browser (Matt, Nov 8 2026): the sheet after a browser's bookmarks file was chosen and read —
// what is in it, the name of the new tab, what happens to the directory levels — and one button to add the tab.
import SwiftUI
import BookmarkManagerCore

struct BrowserImportResult: Identifiable {
    let id = UUID()
    let url: URL
    let file: BrowserBookmarks.File
}

struct BrowserImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: BrowserImportResult
    /// the sentences to show after the tab was added
    let done: ([String]) -> Void
    @State private var tabName: String
    @State private var problem: String?

    init(result: BrowserImportResult, done: @escaping ([String]) -> Void) {
        self.result = result; self.done = done
        _tabName = State(initialValue: result.file.suggestedTabName)
    }

    private var file: BrowserBookmarks.File { result.file }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 22)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.url.lastPathComponent).font(DS.heading).lineLimit(1)
                    Text(file.browser.map { "A bookmarks file from \($0)." } ?? "A browser's bookmarks file.").font(DS.secondary).foregroundStyle(.secondary)
                }
            }
            Form {
                Field("Name of the new tab", $tabName, "Safari bookmarks")
                LabeledContent("Coming in") { Text(counts) }
                Text(levelsText).font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if file.skipped > 0 || file.emptyFolders > 0 {
                    Text(leftOut).font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }
            .formStyle(.grouped)
            Text("The file's folders become directories inside the new tab, in the browser's order; its links become bookmarks. Your other tabs stay as they are. Nothing is deleted from the browser.")
                .font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add the tab") { add() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(file.bookmarks == 0)
            }
        }
        .padding(20).frame(width: 560, height: 440)
    }

    private var counts: String {
        let d = file.folders, b = file.bookmarks
        if b == 0 { return "No bookmarks at all — nothing to add." }
        return "\(d) director\(d == 1 ? "y" : "ies") and \(b) bookmark\(b == 1 ? "" : "s")"
    }
    private var levelsText: String {
        let have = model.library.maxDepth, need = file.levels, top = Library.depthRange.upperBound
        if need == 0 { return "It has no folders: every bookmark lands in the tab itself." }
        if need <= have { return "Its folders go \(need) level\(need == 1 ? "" : "s") deep, which fits the directory levels you have (\(have))." }
        if need <= top { return "Its folders go \(need) levels deep, so the directory levels (Settings → General) will be raised from \(have) to \(need)." }
        return "Its folders go \(need) levels deep — more than the \(top) allowed. The levels will be raised to \(top); anything deeper is folded into the directory above it (no bookmark is lost)."
    }
    private var leftOut: String {
        var parts: [String] = []
        if file.skipped > 0 { parts.append("\(file.skipped) item\(file.skipped == 1 ? " that isn't" : "s that aren't") a web address (bookmarklets, say)") }
        if file.emptyFolders > 0 { parts.append("\(file.emptyFolders) empty folder\(file.emptyFolders == 1 ? "" : "s")") }
        return "Left out: " + parts.joined(separator: ", and ") + "."
    }

    private func add() {
        // the refusal (a blank name) is shown here, in the sheet, not as a notice behind it — checked on its own,
        // so the import is built once, not twice (review, Nov 8 2026)
        do { try Transfer.checkTabName(tabName) }
        catch { problem = (error as? BMError)?.message ?? error.localizedDescription; return }
        // nil: it didn't happen (the save failed, say) — the notice behind the sheet says why, so the sheet goes
        // away and the Settings pane is NOT told it was imported
        guard let notes = model.importBrowser(file, tabName: tabName) else { dismiss(); return }
        done(notes)
        dismiss()
    }
}

// Settings (⌘, or the gear): General (the browser, directory levels, site icons, where things are kept),
// Color codes, Appearance, Export & import (with Validate).
import SwiftUI
import UniformTypeIdentifiers
import BookmarkManagerCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            ColorCodesPane().tabItem { Label("Color codes", systemImage: "paintpalette") }.tag("colors")
            AppearancePane().tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }.tag("appearance")
            TransferPane().tabItem { Label("Export & import", systemImage: "square.and.arrow.up.on.square") }.tag("transfer")
        }
        .frame(width: 680, height: 560)
    }
}

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject var model: AppModel
    @State private var browsers: [Browser] = []
    @State private var depth = 2
    @State private var depthProblem: String?
    @State private var showLinkReport = false

    var body: some View {
        Form {
            Section {
                Picker("Open bookmarks in", selection: $model.settings.browser) {
                    Text("System default" + (Browsers.defaultName().map { " (\($0))" } ?? "")).tag(String?.none)
                    ForEach(browsers) { b in Text(b.name).tag(String?.some(b.id)) }
                    if let chosen = model.settings.browser, !browsers.contains(where: { $0.id == chosen }) {
                        Text("Not installed any more").tag(String?.some(chosen))
                    }
                }
                Text("Every bookmark opens in this browser when you click its name. The list is the browsers installed on this Mac; the Mac's own default can be any app.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            Section {
                Picker("Directory levels inside a tab", selection: $depth) {
                    ForEach(Library.depthRange, id: \.self) { d in Text(levelsLabel(d)).tag(d) }
                }
                .onChange(of: depth) { _, d in
                    guard d != model.library.maxDepth else { return }
                    // a refusal is shown here, under the picker (a notice would open behind this window)
                    if let why = model.reason({ try $0.setMaxDepth(d) }) { depthProblem = why; depth = model.library.maxDepth; return }
                    depthProblem = nil
                    model.setMaxDepth(d)
                    if model.library.maxDepth != d { depth = model.library.maxDepth }
                }
                Text(depthProblem ?? "2 means a directory and one sub-directory in it (the usual). It can't be lowered while a deeper directory exists; move or delete those first.")
                    .font(DS.secondary).foregroundStyle(depthProblem == nil ? Color.secondary : Theme.problem)
            }
            Section("Secrets") {
                Picker("Hide a secret window after", selection: $model.settings.secretHideMinutes) {
                    ForEach([1, 2, 5, 10, 30], id: \.self) { m in Text("\(m) minute\(m == 1 ? "" : "s")").tag(m) }
                    Text("Never").tag(0)
                }
                Text("An open secret window closes by itself after this long without being used. Clicking into it starts the clock again.")
                    .font(DS.secondary).foregroundStyle(.secondary)
                Toggle("Ask for Touch ID before showing a secret", isOn: $model.settings.touchIDForSecrets)
                    .onChange(of: model.settings.touchIDForSecrets) { _, on in if !on { SecretGate.forget() } }
                Text(SecretGate.available
                     ? "Touch ID, or your Mac's password where there is no Touch ID. One check covers the next minute, so several secrets in a row ask once."
                     : "This Mac has no Touch ID and no login password to check against, so the option can't do anything here.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            Section("Links") {
                HStack(spacing: 10) {
                    Button("Check every address…") { model.checkLinks(inMainWindow: false); showLinkReport = true }.disabled(model.linkCheckRunning)
                    if model.linkCheckRunning { ProgressView().controlSize(.small) }
                    Spacer()
                    if model.linkReport != nil { Button("Last results…") { showLinkReport = true } }
                }
                Text(lastCheckText).font(DS.secondary).foregroundStyle(.secondary)
                Picker("Check all addresses on their own", selection: $model.settings.linkCheckDays) {
                    Text("Never").tag(0); Text("Once a week").tag(7); Text("Once a month").tag(30)
                }
                Text("Each address is asked for once, a few at a time, and only when you ask — by this button, by right-click → Check links in this directory, or by this schedule, which runs quietly a few seconds after launch and puts a line above the list when something didn't answer. Problem rows keep a red mark until the next check.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Fetch site icons", isOn: $model.settings.fetchIcons)
                Text("Each site's icon is fetched once from its address and kept on this Mac; a site without one shows the link glyph. Turned off, nothing is fetched (icons already here still show).")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Bookmark Manager") { Text(BookmarkManagerCore.version) }
                LabeledContent("Bookmarks, secrets and settings") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.store.folder.path).font(DS.mono).textSelection(.enabled)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.url]) }.buttonStyle(.link).foregroundStyle(Theme.accent).font(DS.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { browsers = Browsers.installed(); depth = model.library.maxDepth }
        .onChange(of: model.library.maxDepth) { _, d in depth = d }
        .sheet(isPresented: $showLinkReport) { LinkReportSheet().environmentObject(model) }
    }

    private var lastCheckText: String {
        guard let r = model.linkReport else { return "No check has run yet." }
        return "Last checked \(r.checkedAt.formatted(date: .abbreviated, time: .shortened)): \(r.summary.lowercased())."
    }

    private func levelsLabel(_ d: Int) -> String {
        switch d {
        case 1: return "1 — directories only"
        case 2: return "2 — directories with sub-directories"
        default: return "\(d) levels"
        }
    }
}

// MARK: - Color codes

struct ColorCodesPane: View {
    @EnvironmentObject var model: AppModel
    @State private var toRemove: ColorCode?

    private static let starters: [(String, RGB)] = [("Later", RGB(0.56, 0.27, 0.68)), ("Family", RGB(0.91, 0.26, 0.52)), ("Money", RGB(0.10, 0.56, 0.62)), ("Archive", RGB(0.45, 0.45, 0.48)), ("Idea", RGB(0.84, 0.66, 0.08)), ("Client", RGB(0.93, 0.53, 0.12))]

    var body: some View {
        Form {
            Section {
                ForEach(model.library.colors) { c in ColorCodeRow(code: c, remove: { toRemove = c }) }
                HStack {
                    Button { add() } label: { Label("Add a color", systemImage: "plus") }.disabled(model.library.colors.count >= ColorCode.maximum)
                    Spacer()
                    Text("\(model.library.colors.count) of \(ColorCode.maximum)").font(DS.secondary).foregroundStyle(.secondary)
                }
            } header: {
                Text("Color codes · give each color a meaning")
            } footer: {
                Text("A bookmark or directory marked with a color gets a light wash of it as its background. Only the name shows here and in the editor — never on the rows. Removing a color clears it from everything that used it.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(removeTitle, isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }), titleVisibility: .visible) {
            Button("Remove color") { if let c = toRemove { model.removeColor(c.id) }; toRemove = nil }
            Button("Cancel", role: .cancel) { toRemove = nil }.keyboardShortcut(.defaultAction)
        } message: { Text(removeMessage) }
    }

    private var removeTitle: String { "Remove the color “\(toRemove?.name ?? "")”?" }
    private var removeMessage: String {
        guard let c = toRemove else { return "" }
        let u = model.library.uses(ofColor: c.id)
        var parts: [String] = []
        if u.bookmarks > 0 { parts.append("\(u.bookmarks) bookmark\(u.bookmarks == 1 ? "" : "s")") }
        if u.folders > 0 { parts.append("\(u.folders) director\(u.folders == 1 ? "y" : "ies")") }
        return parts.isEmpty ? "Nothing uses it." : "It is cleared from \(parts.joined(separator: " and ")). They keep everything else."
    }

    private func add() {
        let used = Set(model.library.colors.map { $0.name.lowercased() })
        let pick = Self.starters.first { !used.contains($0.0.lowercased()) } ?? ("New color", RGB(0.5, 0.5, 0.5))
        model.addColor(name: pick.0, rgb: pick.1)
    }
}

/// One color code: its swatch (click to change), its name, a preview row, Remove.
struct ColorCodeRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let code: ColorCode
    let remove: () -> Void
    @State private var color: Color = .gray
    @State private var name = ""
    @State private var loaded = false
    @State private var nameSave: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden().frame(width: 44)
                .help("Change the color").accessibilityLabel("Color for \(code.name)")
            PlainTextField("Name", text: $name, label: "Name for this color").frame(width: 150)
            HStack(spacing: 8) {
                Badge(text: name.isEmpty ? "Unnamed" : name, fill: color.opacity(0.2), color: color)
                Text("A bookmark row").font(DS.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(scheme == .dark ? 0.26 : 0.18), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            Button("Remove", action: remove).controlSize(.small)
        }
        .onAppear { color = code.rgb.color; name = code.name; DispatchQueue.main.async { loaded = true } }
        .onChange(of: code) { _, c in if c.name != name { name = c.name }; if c.rgb != RGB(color) { color = c.rgb.color } }
        .onChange(of: color) { _, c in guard loaded else { return }; let rgb = RGB(c); if rgb != code.rgb { model.updateColor(code.id, rgb: rgb) } }
        .onChange(of: name) { _, n in
            guard loaded else { return }
            // saved once typing pauses, not on every letter (each save rewrites the library file)
            nameSave?.cancel()
            nameSave = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                let t = n.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, t != code.name { model.updateColor(code.id, name: t) }
            }
        }
        .onDisappear { nameSave?.cancel(); let t = name.trimmingCharacters(in: .whitespaces); if loaded, !t.isEmpty, t != code.name { model.updateColor(code.id, name: t) } }
    }
}

// MARK: - Export & import

struct ValidationResult: Identifiable {
    let id = UUID()
    let report: ValidationReport
    let url: URL
    let file: ExportFile?
}

struct TransferPane: View {
    @EnvironmentObject var model: AppModel
    @State private var includeSecrets = false
    @State private var message: String?
    @State private var messageIsProblem = false
    @State private var result: ValidationResult?
    @State private var pendingImport: ValidationResult?
    @State private var replacePending: ValidationResult?

    var body: some View {
        Form {
            Section("Export") {
                Text("Everything in one .json file: the tabs, directories, sub-directories and bookmarks with their descriptions, addresses, tags and colors, the color codes, and the directory-levels setting. Easy to read and to keep as a backup.")
                    .font(DS.secondary).foregroundStyle(.secondary)
                Toggle("Include the secrets", isOn: $includeSecrets)
                Text(includeSecrets ? "The file will hold every secret decrypted, in plain text. Keep it somewhere safe and delete it when you are done with it." : "Secrets are left out. A bookmark that has one is still marked, so an import here keeps the secret it already has.")
                    .font(DS.secondary).foregroundStyle(includeSecrets ? Theme.attention : .secondary)
                Button("Export…") { export() }
            }
            Section("Import") {
                Text("Validate reads a file and lists every problem with where it is, without changing anything. Import validates first; then the file either replaces everything here or its tabs are added beside yours.")
                    .font(DS.secondary).foregroundStyle(.secondary)
                HStack {
                    Button("Validate a file…") { pick(thenImport: false) }
                    Button("Import…") { pick(thenImport: true) }
                }
            }
            if let message { Text(message).font(DS.secondary).foregroundStyle(messageIsProblem ? Theme.problem : .primary) }
        }
        .formStyle(.grouped)
        .sheet(item: $result) { r in ValidationSheet(result: r) { mode in finish(r, mode: mode) } }
        .confirmationDialog("How should “\(pendingImport?.url.lastPathComponent ?? "")” come in?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("Add its tabs beside mine") { if let p = pendingImport { finish(p, mode: .addTabs) }; pendingImport = nil }
            Button("Replace everything here…") { replacePending = pendingImport; pendingImport = nil }
            Button("Cancel", role: .cancel) { pendingImport = nil }.keyboardShortcut(.defaultAction)
        } message: {
            Text("\(pendingImport?.report.counts ?? "") “Add” brings its tabs in as copies and leaves yours as they are. “Replace” throws away what is here first — export a copy of yours before, if you want one.")
        }
        .confirmationDialog("Replace everything here with “\(replacePending?.url.lastPathComponent ?? "")”?", isPresented: Binding(get: { replacePending != nil }, set: { if !$0 { replacePending = nil } }), titleVisibility: .visible) {
            Button("Replace everything") { if let p = replacePending { finish(p, mode: .replace) }; replacePending = nil }
            Button("Cancel", role: .cancel) { replacePending = nil }.keyboardShortcut(.defaultAction)
        } message: { Text("Every tab, directory and bookmark here is thrown away first. This can't be undone.") }
    }

    private func export() {
        let panel = NSSavePanel()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Bookmark Manager \(f.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportData(includeSecrets: includeSecrets).write(to: url, options: .atomic)
            if includeSecrets { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
            let n = model.library.allBookmarks.count
            message = "Exported \(model.library.tabs.count) tab\(model.library.tabs.count == 1 ? "" : "s") and \(n) bookmark\(n == 1 ? "" : "s") to \(url.lastPathComponent)" + (includeSecrets ? ", secrets included." : ".")
            messageIsProblem = false
        } catch { message = "Could not write the file: \(error.localizedDescription)"; messageIsProblem = true }
    }

    private func pick(thenImport: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { message = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"; messageIsProblem = true; return }
        let report = Transfer.validate(data)
        let r = ValidationResult(report: report, url: url, file: try? Transfer.read(data))
        if thenImport && report.canImport && report.notes.isEmpty { pendingImport = r } else { result = r }
    }

    private func finish(_ r: ValidationResult, mode: ImportMode) {
        guard let f = r.file else { return }
        let notes = model.importFile(f, mode: mode)
        message = (mode == .replace ? "Imported \(r.url.lastPathComponent), replacing what was here. " : "Imported \(r.url.lastPathComponent). ") + notes.joined(separator: " ")
        messageIsProblem = false
        result = nil
    }
}

/// What Validate found: the counts, every problem with its place, and (when the file is fine) the import buttons.
struct ValidationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: ValidationResult
    let importIt: (ImportMode) -> Void
    @State private var confirmReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: result.report.canImport ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22)).foregroundStyle(result.report.canImport ? Theme.good : Theme.problem)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.url.lastPathComponent).font(DS.heading).lineLimit(1)
                    Text(headline).font(DS.secondary).foregroundStyle(.secondary)
                }
            }
            if result.report.problems.isEmpty {
                Text("Nothing wrong with it. It can be imported.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(result.report.problems.enumerated()), id: \.offset) { i, p in
                            if i > 0 { Divider() }
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: p.stops ? "xmark.circle.fill" : "info.circle.fill").foregroundStyle(p.stops ? Theme.problem : Theme.attention).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.place).fontWeight(.semibold)
                                    Text(p.text).font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.radius))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).strokeBorder(Color.primary.opacity(0.1)))
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if result.report.canImport && result.file != nil {
                    Button("Add its tabs beside mine") { importIt(.addTabs); dismiss() }
                    Button("Replace everything here…") { confirmReplace = true }
                }
            }
        }
        .padding(20).frame(width: 600, height: 460)
        .confirmationDialog("Replace everything here with “\(result.url.lastPathComponent)”?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace everything") { importIt(.replace); dismiss() }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text("Every tab, directory and bookmark here is thrown away first. Export a copy of yours before, if you want one.") }
    }

    private var headline: String {
        let r = result.report
        if !r.canImport { return "Can't be imported yet: \(r.stops.count) problem\(r.stops.count == 1 ? "" : "s") to fix. " + r.counts }
        if !r.notes.isEmpty { return "Can be imported, with \(r.notes.count) note\(r.notes.count == 1 ? "" : "s"). " + r.counts }
        return "Looks good. " + r.counts
    }
}

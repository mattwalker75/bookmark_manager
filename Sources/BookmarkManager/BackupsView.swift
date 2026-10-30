// Settings → Backups (Matt, Oct 29 2026): on/off, where, when, how many to keep, the secret key and the
// passphrase, the list of backups with Verify / Restore / Keep, and the fresh-Mac way in: Restore from a file…
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BookmarkManagerCore

struct BackupsPane: View {
    @EnvironmentObject var model: AppModel
    @State private var message: String?
    @State private var messageIsProblem = false
    @State private var checking: URL?
    @State private var keeping: BackupEntry?
    @State private var passphraseSheet = false
    @State private var confirmDelete: BackupEntry?

    private var folderPath: String { model.backupStore.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    var body: some View {
        Form {
            Section {
                Toggle("Enable backups", isOn: $model.settings.backupsEnabled)
                LabeledContent("Where") {
                    HStack(spacing: 8) {
                        Text(folderPath).font(DS.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button("Choose…") { chooseFolder() }
                        if model.settings.backupFolder != nil { Button("Default") { model.settings.backupFolder = nil; model.refreshBackups() } }
                    }
                }
                Picker("When", selection: $model.settings.backupWhen) { ForEach(BackupWhen.allCases) { w in Text(w.label).tag(w) } }
                Picker("Keep the latest", selection: $model.settings.backupKeep) { ForEach([5, 7, 14, 30, 90], id: \.self) { n in Text("\(n) backups").tag(n) } }
                Text("A backup is one file holding everything — tabs, directories, bookmarks, color codes and the secrets — written only when something changed since the last one. Older backups fall off the end; the ones you mark as kept never do. Back up into a folder your Mac already copies elsewhere (iCloud Drive, Time Machine, Data Syncer) and you have it off this disk too.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            .disabled(false)
            Section("The secrets inside") {
                Picker("Written as", selection: Binding(get: { model.settings.backupSecretsPlain }, set: { model.setBackupSecretsPlain($0) })) {
                    Text("Sealed with this Mac's secret key").tag(false)
                    Text("Plain text, readable by anyone with the file").tag(true)
                }
                if model.settings.backupSecretsPlain {
                    Text("Every secret is written in the clear in each backup from now on. Anyone who can open the file — or any copy Time Machine, iCloud or a sync tool makes of it — can read them. Choose this only when you mean it, for instance for a backup you will lock up some other way.")
                        .font(DS.secondary).foregroundStyle(Theme.problem)
                } else {
                    Text("The secrets in every backup are sealed with this Mac's secret key (secret.key), the same as on disk — so a backup is safe to copy anywhere, and opens on a Mac that has the key file. Save a copy of the key somewhere safe once (a password manager, a USB stick): on a new Mac, Restore asks for it.")
                        .font(DS.secondary).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Save a copy of the secret key…") { saveKey() }
                    Button("Show the key in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.secrets.keyURL]) }
                }
                HStack(spacing: 8) {
                    Text(model.settings.backupPassphrase == nil ? "No passphrase set." : "A passphrase is set: backups also open with it.")
                    Spacer()
                    Button(model.settings.backupPassphrase == nil ? "Set a passphrase…" : "Change…") { passphraseSheet = true }
                    if model.settings.backupPassphrase != nil { Button("Remove") { model.clearBackupPassphrase() } }
                }
                Text("Optional. With a passphrase, every backup from then on also opens with the words alone — nothing to keep but the passphrase. Restore asks for it when this Mac doesn't have the key.")
                    .font(DS.secondary).foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 8) {
                    Text("Backups here · \(model.backups.count)" + (model.backups.filter(\.kept).isEmpty ? "" : " (\(model.backups.filter(\.kept).count) kept)")).fontWeight(.semibold)
                    Spacer()
                    Button("Back up now") { let s = model.backUp(reason: .manual, force: true); message = s; messageIsProblem = s?.hasPrefix("Backed up") == false }
                    Button("Restore from a file…") { pickFile() }
                    Button("Show in Finder") { try? FileManager.default.createDirectory(at: model.backupStore.folder, withIntermediateDirectories: true); NSWorkspace.shared.activateFileViewerSelecting([model.backupStore.folder]) }
                }
                if model.backups.isEmpty {
                    Text("No backups yet. The first one is written on the next launch (or quit), or now with Back up now.").font(DS.secondary).foregroundStyle(.secondary)
                }
                ForEach(model.backups) { e in row(e) }
                if let message { Text(message).font(DS.secondary).foregroundStyle(messageIsProblem ? Theme.problem : Color.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshBackups() }
        .sheet(item: $checking) { url in BackupCheckSheet(url: url) { message = $0; messageIsProblem = false }.environmentObject(model) }
        .sheet(item: $keeping) { e in KeepSheet(entry: e).environmentObject(model) }
        .sheet(isPresented: $passphraseSheet) { PassphraseSheet { message = $0; messageIsProblem = false }.environmentObject(model) }
        .confirmationDialog("Delete the backup from \(confirmDelete.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete") { if let e = confirmDelete { model.deleteBackup(e) }; confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }.keyboardShortcut(.defaultAction)
        } message: { Text("The file is removed from the backups folder. Nothing in the app changes.") }
    }

    private func row(_ e: BackupEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: e.kept ? "star.fill" : "doc").foregroundStyle(e.kept ? DS.key : Color.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.createdAt.formatted(date: .abbreviated, time: .shortened)).fontWeight(.semibold)
                    Text("— \(e.reason.label)").foregroundStyle(.secondary)
                    if e.kept { Text("· kept").foregroundStyle(DS.key) }
                    if !e.note.isEmpty { Text("— “\(e.note)”").foregroundStyle(.secondary).lineLimit(1) }
                }
                Text(e.readable ? "\(e.counts.text) · \(sizeText(e.size))" : "Not a readable backup file").font(DS.secondary).foregroundStyle(e.readable ? Color.secondary : Theme.problem)
            }
            Spacer()
            if e.readable {
                Button("Verify…") { checking = e.url }.controlSize(.small)
                Button(e.kept ? "Unkeep" : "Keep…") { if e.kept { model.setKept(e, kept: false, note: "") } else { keeping = e } }.controlSize(.small)
            }
            Button { confirmDelete = e } label: { Image(systemName: "trash") }.controlSize(.small).help("Delete this backup file").accessibilityLabel("Delete")
        }
        .padding(.vertical, 2)
        .background(e.kept ? DS.key.opacity(0.08) : Color.clear)
    }

    private func sizeText(_ n: Int) -> String { n < 1_000_000 ? "\(max(1, n / 1024)) KB" : String(format: "%.1f MB", Double(n) / 1_048_576) }

    private func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.allowsMultipleSelection = false
        p.message = "Choose the folder the backups are written to."
        guard p.runModal() == .OK, let u = p.url else { return }
        model.settings.backupFolder = u.path
        model.refreshBackups()
    }
    private func saveKey() {
        let p = NSSavePanel(); p.nameFieldStringValue = "Bookmark Manager secret.key"; p.message = "Keep this copy somewhere safe: it opens the secrets in your backups."
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try model.saveKeyCopy(to: u); message = "The key was saved as \(u.lastPathComponent). Anyone with it and a backup can read the secrets, so keep it like a password."; messageIsProblem = false }
        catch { message = "The key could not be saved: \((error as? BMError)?.message ?? error.localizedDescription)"; messageIsProblem = true }
    }
    private func pickFile() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = false; p.canChooseDirectories = false
        p.allowedContentTypes = [UTType(filenameExtension: Backup.fileExtension) ?? .data, .json]
        p.message = "Choose a Bookmark Manager backup file (.bmbackup) — from this Mac or another."
        guard p.runModal() == .OK, let u = p.url else { return }
        checking = u
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Verify (and then Restore) one backup file: with this Mac's key, a key file, or the passphrase.
struct BackupCheckSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let done: (String) -> Void
    @State private var result: Result<BackupCheck, BMError>?
    @State private var passphrase = ""
    @State private var problem: String?
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(url.lastPathComponent).font(DS.heading).lineLimit(1).truncationMode(.middle)
            switch result {
            case .none: ProgressView("Checking…")
            case .failure(let e):
                HStack(alignment: .top, spacing: 10) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.problem); Text(e.message).fixedSize(horizontal: false, vertical: true) }
            case .success(let c): report(c)
            }
            if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if case .success(let c) = result, c.canRestore, !confirmRestore {
                    Button("Restore…") { confirmRestore = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20).frame(width: 620, height: 420)
        .onAppear { result = model.checkBackup(at: url) }
    }

    @ViewBuilder private func report(_ c: BackupCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: c.canRestore ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(c.canRestore ? Theme.good : Theme.attention)
            VStack(alignment: .leading, spacing: 4) {
                Text("Made \(c.file.createdAt.formatted(date: .abbreviated, time: .shortened)), \(c.file.reason.label)" + (c.file.kept ? " · kept" : "") + (c.file.note.isEmpty ? "" : " — “\(c.file.note)”"))
                Text(c.file.counts.text + (c.file.library.colors.isEmpty ? "" : " · \(c.file.library.colors.count) color codes") + " · \(c.file.library.maxDepth) directory levels").font(DS.secondary).foregroundStyle(.secondary)
                if c.secretsInClear { Text("The \(c.file.counts.secrets) secrets are in plain text in this file — anyone who has it can read them.").font(DS.secondary).foregroundStyle(Theme.attention) }
                else if !c.hasSecrets { Text("No secrets inside.").font(DS.secondary).foregroundStyle(.secondary) }
                else if c.secretsReadable { Text("All \(c.file.counts.secrets) secrets open with \(c.openedWith).").font(DS.secondary).foregroundStyle(Theme.good) }
                else { Text("The \(c.file.counts.secrets) secrets inside don't open with this Mac's key.").font(DS.secondary).foregroundStyle(Theme.attention) }
                ForEach(Array(c.report.problems.enumerated()), id: \.offset) { _, p in
                    Text("\(p.place): \(p.text)").font(DS.secondary).foregroundStyle(p.stops ? Theme.problem : Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if c.hasSecrets, !c.secretsReadable {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open the secrets with the key file from the Mac that made this backup, or with its passphrase.").font(DS.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Choose the key file…") { chooseKey() }
                        if c.acceptsPassphrase {
                            SecureField("Passphrase", text: $passphrase).frame(width: 200)
                            Button("Unlock") { unlock() }.disabled(passphrase.isEmpty)
                        } else { Text("This backup has no passphrase on it.").font(DS.secondary).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        if confirmRestore {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore this backup?").fontWeight(.semibold)
                    Text("Everything here is replaced by what it holds: \(c.file.counts.text). A kept backup of the way things are right now is written first, so this can be undone from this list.").font(DS.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Spacer(); Button("Cancel") { confirmRestore = false }; Button("Restore") { restore(c) }.buttonStyle(.borderedProminent) }
                }
            }
        }
    }

    private func chooseKey() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = false; p.canChooseDirectories = false
        p.message = "Choose the secret.key file (or the copy you saved) from the Mac that made this backup."
        guard p.runModal() == .OK, let k = p.url else { return }
        result = model.checkBackup(at: url, keyFile: k)
        if case .failure(let e) = result! { problem = e.message } else { problem = nil }
    }
    private func unlock() {
        let r = model.checkBackup(at: url, passphrase: passphrase)
        if case .failure(let e) = r { problem = e.message } else { problem = nil; result = r }
    }
    private func restore(_ c: BackupCheck) {
        let s = model.restoreBackup(c)
        done(s)
        dismiss()
    }
}

/// Keep…: an optional note, then the star.
struct KeepSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: BackupEntry
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep the backup from \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))").font(DS.heading)
            Text("A kept backup never falls off the end of the list, however many newer ones there are.").font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form { Field("Note", $note, "Optional — why this one matters (“before the big re-sort”)") }.formStyle(.grouped)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Keep") { model.setKept(entry, kept: true, note: note); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
        .padding(20).frame(width: 480)
    }
}

/// Set or change the backup passphrase.
struct PassphraseSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let done: (String) -> Void
    @State private var one = ""
    @State private var two = ""
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.settings.backupPassphrase == nil ? "Set a passphrase for the backups" : "Change the backup passphrase").font(DS.heading)
            Text("From the next backup on, the secrets inside also open with this passphrase — on any Mac, with no key file. Choose words you will remember; there is no way to recover a lost passphrase (the key file still opens those backups).").font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                SecureField("Passphrase", text: $one)
                SecureField("Again", text: $two)
                if let problem { Text(problem).font(DS.secondary).foregroundStyle(Theme.problem) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set") {
                    guard one == two else { problem = "The two don't match."; return }
                    do { try model.setBackupPassphrase(one); done("The passphrase is set; the next backup carries it."); dismiss() }
                    catch { problem = (error as? BMError)?.message ?? error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(one.isEmpty)
            }
        }
        .padding(20).frame(width: 480)
    }
}

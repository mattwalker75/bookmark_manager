// The app: one window (tabs across the top, the folder tree on the left, the selected directory's bookmarks on
// the right, the search box in the title bar), Settings, and the small secret windows.
import SwiftUI
import BookmarkManagerCore

@main
struct BookmarkManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Bookmark Manager", id: "main") {
            MainWindow()
                .environmentObject(model)
                .environmentObject(model.icons)
                .preferredColorScheme(model.lookInForce.colorScheme)
                .tint(Theme.accent)
                .font(DS.body)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    model.addSampleIfAsked()
                    model.runScheduledLinkCheckIfDue()
                    model.backupAtLaunchIfDue()
                    AppDelegate.beforeQuit = { model.backupOnQuit() }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bookmark…") { model.sheet = .newBookmark(model.selectedPath) }.keyboardShortcut("n")
                Button("New Directory…") { model.sheet = .newFolder(model.newFolderPath) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Tab…") { model.sheet = .newTab }.keyboardShortcut("t")
            }
            CommandMenu("Bookmarks") {
                Button("Find…") { model.focusSearch += 1 }.keyboardShortcut("f")
                Divider()
                // while search results are showing, these would act on the hidden selection: off until the search is cleared
                Button("Edit This Directory…") { if let f = model.currentFolder { model.sheet = model.selectedPath.isTabRoot ? .renameTab(f) : .editFolder(f) } }.keyboardShortcut("e").disabled(model.isSearching)
                Button("Sort This Directory by Name") { model.sortByName(model.selectedPath) }.disabled(model.isSearching)
                Divider()
                Button("Rename Tab…") { if let t = model.currentTab { model.sheet = .renameTab(t) } }.disabled(model.isSearching)
                Divider()
                Button("Check Links in This Directory…") { model.checkLinks(in: model.selectedPath) }.disabled(model.isSearching || model.linkCheckRunning)
                Button("Check Every Address…") { model.checkLinks() }.disabled(model.linkCheckRunning)
                Divider()
                // the keyboard (Matt, Oct 29 2026); ↑ ↓ Return Space are handled in the window itself (KeyboardDriver)
                Button("Copy Address") { model.copyFocusedAddress() }.keyboardShortcut("l").disabled(model.focusedBookmark.map(\.isSecretOnly) ?? true)
                Button("Show Secret") { model.showFocusedSecret() }.disabled(!(model.focusedBookmark?.hasSecret ?? false))
                Button("Enclosing Directory") { model.goUp() }.keyboardShortcut(.upArrow, modifiers: .command).disabled(model.isSearching || model.selectedPath.isTabRoot)
            }
            CommandMenu("Tabs") {
                ForEach(Array(model.library.tabs.prefix(9).enumerated()), id: \.element.id) { i, tab in
                    Button(tab.name) { model.selectTab(tab.id) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Next Tab") { model.selectNextTab(1) }.keyboardShortcut(.tab, modifiers: .control).disabled(model.library.tabs.count < 2)
                Button("Previous Tab") { model.selectNextTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift]).disabled(model.library.tabs.count < 2)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .preferredColorScheme(model.lookInForce.colorScheme)
                .tint(Theme.accent)
                .font(DS.body)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ n: Notification) {
        // one copy at a time: two copies on one bookmarks file would overwrite each other's changes (found in
        // review); the copy already running is brought forward instead. (Tests and the bare binary carry no bundle
        // id, so they are left alone.)
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty,
              let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { return }
        other.activate()
        NSApp.terminate(nil)
    }

    // a plain utility: closing its last window quits it
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    /// Runs just before the app quits (the "when the app quits" backup).
    static var beforeQuit: (() -> Void)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.beforeQuit?()
        return .terminateNow
    }

    /// The Dock icon clicked while only a secret window is open: the main window comes back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }), !main.isVisible { main.makeKeyAndOrderFront(nil); return false }
        return true
    }
}

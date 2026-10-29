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
                .preferredColorScheme(model.lookInForce.colorScheme)
                .tint(Theme.accent)
                .font(DS.body)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { model.addSampleIfAsked() }
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
                Button("Edit This Directory…") { if let f = model.currentFolder { model.sheet = model.selectedPath.isTabRoot ? .renameTab(f) : .editFolder(f) } }.keyboardShortcut("e")
                Button("Sort This Directory by Name") { model.sortByName(model.selectedPath) }
                Divider()
                Button("Rename Tab…") { if let t = model.currentTab { model.sheet = .renameTab(t) } }
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
    // a plain utility: closing its last window quits it
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

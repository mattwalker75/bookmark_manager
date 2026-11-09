// The two result lists — the link check and the duplicates — in windows of their own (Matt, Nov 8 2026): they
// used to be sheets, and "Show in place" or "Edit…" had to close them to reach the main window, so the list had
// to be opened again for every bookmark. Now one window each stays open beside the main window until Done or
// its close button; a second ask brings the same window forward. Resizable, and the place it was left is kept.
import SwiftUI
import AppKit
import BookmarkManagerCore

@MainActor
enum ReportWindows {
    enum Kind: String, CaseIterable {
        case links, duplicates
        var title: String { self == .links ? "Link check" : "Duplicate bookmarks" }
    }
    private static var windows: [Kind: NSWindow] = [:]
    /// the size a window opens at the first time (the old sheets were this size); it can be made smaller than that
    static let openingSize = NSSize(width: 820, height: 600)
    static let floor = NSSize(width: 640, height: 420)

    static func isOpen(_ k: Kind) -> Bool { windows[k] != nil }

    static func show(_ k: Kind, model: AppModel) {
        if let w = windows[k] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: openingSize), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = k.title
        w.isReleasedWhenClosed = false
        w.contentMinSize = floor
        w.delegate = Closer.shared
        switch k {
        case .links: w.contentView = NSHostingView(rootView: ReportRoot(model: model) { LinkReportView(close: { close(k) }) })
        case .duplicates: w.contentView = NSHostingView(rootView: ReportRoot(model: model) { DuplicatesView(close: { close(k) }) })
        }
        w.center()
        w.setFrameAutosaveName("ReportWindow-\(k.rawValue)")   // where it was left last time, when there was a last time
        windows[k] = w
        w.makeKeyAndOrderFront(nil)
    }

    static func close(_ k: Kind) { windows[k]?.close() }

    /// Bring the main window forward without closing this one (Show in place, Edit…).
    static func frontMain() { NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
    /// Edit… from a row: the editor sheet on the main window — unless one is already up, which then just comes
    /// forward (review, Nov 8 2026: a second Edit… used to replace the open editor and lose what was typed in it).
    static func edit(_ b: Bookmark, model: AppModel) {
        if model.sheet == nil { model.sheet = .editBookmark(b) }
        frontMain()
    }

    private final class Closer: NSObject, NSWindowDelegate {
        static let shared = Closer()
        func windowWillClose(_ n: Notification) {
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { if let k = windows.first(where: { $0.value === w })?.key { windows.removeValue(forKey: k) } }
        }
    }
}

/// The look every report window shares with the rest of the app.
private struct ReportRoot<Content: View>: View {
    @ObservedObject var model: AppModel
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            // a refusal raised by a click here is an alert on the MAIN window: bring it forward so it is seen
            // (review, Nov 8 2026)
            .onChange(of: model.notice?.id) { _, id in if id != nil { ReportWindows.frontMain() } }
            .environmentObject(model).environmentObject(model.icons)
            .font(DS.body)
            .preferredColorScheme(model.lookInForce.colorScheme)
            .tint(Theme.accent)
    }
}

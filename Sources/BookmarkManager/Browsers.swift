// The browsers installed on this Mac, and opening an address in the one chosen in Settings (or the Mac's default).
import AppKit

struct Browser: Identifiable, Hashable {
    /// the bundle identifier (what the settings keep)
    let id: String
    let name: String
    let url: URL
}

enum Browsers {
    /// Browsers known by their bundle id (a terminal like iTerm also claims https:, so claiming it is not enough).
    static let known = ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
                        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "com.brave.Browser", "com.brave.Browser.beta",
                        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "company.thebrowser.Browser", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
                        "com.vivaldi.Vivaldi", "com.duckduckgo.macos.browser", "com.kagi.kagimacOS", "app.zen-browser.zen", "org.torproject.torbrowser", "com.sigmaos.sigmaos.macos"]

    /// The browsers on this Mac, by name: apps that open web addresses AND local files (every real browser does;
    /// a terminal that claims https: does not), or that are known browsers. (Bookmark Manager itself is left out.)
    static func installed() -> [Browser] {
        let probe = URL(string: "https://example.com/")!
        var seen = Set<String>(), out: [Browser] = []
        for u in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let b = Bundle(url: u), let id = b.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { continue }
            guard known.contains(id) || declares(b, scheme: "file") else { continue }
            out.append(Browser(id: id, name: displayName(u), url: u))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func declares(_ b: Bundle, scheme: String) -> Bool {
        guard let types = b.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains { $0.lowercased() == scheme } ?? false }
    }

    /// The Mac's default browser's name ("Safari"), for the "System default" choice.
    static func defaultName() -> String? {
        guard let u = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com/")!) else { return nil }
        return displayName(u)
    }

    static func displayName(_ u: URL) -> String {
        let n = FileManager.default.displayName(atPath: u.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    /// Opens `url` in the browser with this bundle id, or the default browser when nil or not installed any more.
    /// `problem` is called with a plain sentence when it could not be opened.
    static func open(_ url: URL, with bundleId: String?, problem: @escaping @MainActor (String) -> Void) {
        if let bundleId, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { Task { @MainActor in problem("\(displayName(app)) didn't open it: \(error.localizedDescription)") } }
            }
            return
        }
        if bundleId != nil {
            // the chosen browser is gone: the default one steps in, and the person is told once
            Task { @MainActor in problem("The browser chosen in Settings isn't installed any more, so the Mac's default browser was used. Pick another in Settings → General.") }
        }
        if !NSWorkspace.shared.open(url) { Task { @MainActor in problem("macOS found no app to open \(url.absoluteString).") } }
    }
}

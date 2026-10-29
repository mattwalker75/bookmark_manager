// What the search box found, grouped by tab: each bookmark or directory with where it lives, what matched, the
// Secret button, and "Show in place" to jump there. Clicking a name still opens it.
import SwiftUI
import BookmarkManagerCore

struct SearchResults: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hits = model.hits
        let words = Library.words(model.query)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Results for “\(model.query.trimmingCharacters(in: .whitespaces))”").font(DS.title).lineLimit(1)
                Text(summary(hits)).font(DS.secondary).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.query = "" }.help("Back to the tabs (Esc in the search box does the same)")
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 12)
            if hits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Nothing matches").font(DS.heading)
                    Text("The search looks at names, addresses and tags in every tab. Every word you type has to be found.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.library.tabs) { tab in
                            let inTab = hits.filter { $0.tabId == tab.id }
                            if !inTab.isEmpty {
                                SectionLabel(tab.name, detail: "· \(inTab.count)")
                                GroupedCard {
                                    ForEach(Array(inTab.enumerated()), id: \.element.id) { i, hit in
                                        if i > 0 { RowDivider(inset: 52) }
                                        HitRow(hit: hit, words: words)
                                    }
                                }
                            }
                        }
                        Text("Results update as you type. “Show in place” switches to the tab, opens the directory and marks the row.")
                            .font(DS.secondary).foregroundStyle(.tertiary).padding(.top, 4)
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summary(_ hits: [SearchHit]) -> String {
        let b = hits.filter { !$0.isFolder }.count, d = hits.count - b
        let tabs = Set(hits.map(\.tabId)).count
        var parts: [String] = []
        if b > 0 { parts.append("\(b) bookmark\(b == 1 ? "" : "s")") }
        if d > 0 { parts.append("\(d) director\(d == 1 ? "y" : "ies")") }
        if parts.isEmpty { return "nothing found" }
        return parts.joined(separator: " and ") + ", in \(tabs) tab\(tabs == 1 ? "" : "s") · names, addresses and tags"
    }
}

struct HitRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let hit: SearchHit
    let words: [String]
    @State private var over = false
    @State private var nameOver = false

    var body: some View {
        HStack(spacing: 12) {
            switch hit.kind {
            case .folder(let f): IconTile(systemName: "folder", color: model.color(f.colorId)?.rgb.color ?? .secondary)
            case .bookmark(let b): SiteIcon(address: b.url)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Highlight.mark(hit.name, words)).fontWeight(.semibold).lineLimit(1)
                        .foregroundStyle(nameOver ? Theme.accent : Color.primary).underline(nameOver)
                        .contentShape(Rectangle())
                        .onHover { nameOver = $0 }
                        .onTapGesture { open() }
                        .accessibilityAddTraits(hit.isFolder ? .isButton : .isLink)
                    if hit.isFolder { Text("· \(Library.levelName(hit.path.depth))").font(DS.secondary).foregroundStyle(.secondary) }
                }
                Text(detail).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if case .bookmark(let b) = hit.kind, b.hasSecret {
                Button { model.showSecret(b) } label: { Label("Secret", systemImage: "key.fill").font(DS.secondary) }.buttonStyle(.bordered).controlSize(.small)
            }
            Button("Show in place") { model.showInPlace(hit) }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(background)
        .contentShape(Rectangle())
        .onHover { over = $0 }
        .contextMenu {
            if case .bookmark(let b) = hit.kind {
                Button("Open") { model.open(b) }
                Button("Copy address") { model.copyAddress(b) }
                Button("Edit…") { model.sheet = .editBookmark(b) }
            } else if case .folder(let f) = hit.kind {
                Button("Open") { model.select(hit.path) ; model.query = "" }
                Button("Edit…") { model.sheet = .editFolder(f) }
            }
            Button("Show in place") { model.showInPlace(hit) }
        }
    }

    private func open() {
        switch hit.kind {
        case .bookmark(let b): model.open(b)
        case .folder: model.query = ""; model.select(hit.path)
        }
    }

    private var detail: AttributedString {
        var s = AttributedString(hit.place)
        if case .bookmark(let b) = hit.kind {
            let extra = hit.matched.filter { $0 != "name" }
            if extra.contains("address") { s += AttributedString(" · ") + Highlight.mark(b.link?.absoluteString ?? b.url, words) }
            let tags = extra.filter { $0.hasPrefix("tag") }
            if !tags.isEmpty { s += AttributedString(" · matched \(tags.joined(separator: ", "))") }
        }
        return s
    }

    private var background: Color {
        var colorId: UUID?
        switch hit.kind { case .bookmark(let b): colorId = b.colorId; case .folder(let f): colorId = f.colorId }
        if let c = model.color(colorId) { return c.rgb.color.opacity(scheme == .dark ? 0.26 : 0.18) }
        return over ? DS.hover(scheme) : Color.clear
    }
}

/// The matched words, marked in the text.
enum Highlight {
    static func mark(_ text: String, _ words: [String]) -> AttributedString {
        var s = AttributedString(text)
        let lower = text.lowercased()
        for w in words where !w.isEmpty {
            var from = lower.startIndex
            while let r = lower.range(of: w, range: from..<lower.endIndex) {
                if let lo = AttributedString.Index(r.lowerBound, within: s), let hi = AttributedString.Index(r.upperBound, within: s) {
                    s[lo..<hi].backgroundColor = Theme.accent.opacity(0.35)
                    s[lo..<hi].font = .system(size: 14, weight: .bold)
                }
                from = r.upperBound
            }
        }
        return s
    }
}

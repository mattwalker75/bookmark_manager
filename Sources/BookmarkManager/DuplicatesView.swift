// The duplicates window (Matt, Nov 8 2026; mockup board "Duplicates sheet" — a window of its own since the same
// day, see `ReportWindows`): every group of bookmarks that point at the same page, each bookmark with where it
// lives — Show in place, Edit…, Delete… (asked first) — and, per group, "Meant to be the same" which marks every
// member so the group is left out from then on (undone in the editor, or here under "Show the ones left out").
// Nothing is changed unless a button is clicked. The window stays open while you work from it.
import SwiftUI
import BookmarkManagerCore

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    /// closes the window (Done)
    let close: () -> Void
    @State private var showKept = false

    var body: some View {
        let r = model.duplicates
        let groups = showKept ? r.groups : r.shown
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: r.shown.isEmpty ? "checkmark.seal.fill" : "doc.on.doc.fill").font(.system(size: 22)).foregroundStyle(r.shown.isEmpty ? Theme.good : Theme.attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.summary).font(DS.heading)
                    Text(detail(r)).font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if groups.isEmpty {
                Text(r.keptAway.isEmpty ? "Nothing to do." : "Nothing to do — the \(r.keptAway.count == 1 ? "one group" : "\(r.keptAway.count) groups") left out \(r.keptAway.count == 1 ? "is" : "are") marked as meant to be the same.").foregroundStyle(.secondary)
            } else {
                GroupedCard {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                                if i > 0 { Divider() }
                                group(g)
                            }
                        }
                    }
                }
                HStack(spacing: 16) {
                    legend(Theme.attention, "same address — letter for letter")
                    legend(Theme.accent, "same page, written differently — http/https, www, a trailing slash, tracking bits after “?”")
                }
                .font(DS.secondary).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if !r.keptAway.isEmpty {
                    Toggle(isOn: $showKept) { Text("Show the \(r.keptAwayBookmarks) left out") }.toggleStyle(.checkbox)
                        .help("The groups marked as meant to be the same, dimmed, with a button to look at them again")
                }
                Spacer()
                Button("Done") { close() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: ReportWindows.floor.width, maxWidth: .infinity, minHeight: ReportWindows.floor.height, maxHeight: .infinity)
    }

    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(t) } }

    private func detail(_ r: DuplicateReport) -> String {
        var s = "Looked just now across every tab · \(r.checked) bookmark\(r.checked == 1 ? "" : "s") with an address"
        if r.keptAwayBookmarks > 0 { s += " · \(r.keptAwayBookmarks) already marked as meant to be the same \(r.keptAwayBookmarks == 1 ? "is" : "are") left out" }
        return s + ". Nothing is changed unless you choose to."
    }

    private func group(_ g: DuplicateGroup) -> some View {
        let color = g.exact ? Theme.attention : Theme.accent
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(g.exact ? "same address" : "same page, written differently").font(DS.secondary).fontWeight(.semibold).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(color, in: Capsule()).fixedSize()
                Text(g.key).font(DS.mono).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 8)
                if g.allKept {
                    Text("meant to be the same").font(DS.secondary).foregroundStyle(.secondary)
                    Button("Look at these again") { model.keepDuplicates(g.bookmarkIds, false) }.controlSize(.small).fixedSize()
                        .help("Take the mark off every bookmark in this group")
                } else {
                    Button("Meant to be the same — keep all \(g.bookmarkIds.count)") { model.keepDuplicates(g.bookmarkIds, true) }.controlSize(.small).fixedSize()
                        .help("Mark these as intended (one bookmark per account, say): the group is left out from then on. Undo in a bookmark's editor.")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            ForEach(g.bookmarkIds, id: \.self) { id in
                if let b = model.library.bookmark(id) {
                    Divider().padding(.leading, 60)
                    DuplicateRow(bookmark: b, showAddress: !g.exact, dimmed: g.allKept)
                }
            }
        }
    }
}

/// One bookmark in a group: its icon, name, place (and address when the group's addresses differ), the buttons.
struct DuplicateRow: View {
    @EnvironmentObject var model: AppModel
    let bookmark: Bookmark
    let showAddress: Bool
    let dimmed: Bool
    @State private var confirmDelete = false

    var body: some View {
        let place = model.library.location(ofBookmark: bookmark.id).map { model.placeName($0) } ?? ""
        HStack(alignment: .center, spacing: 12) {
            SiteIcon(address: bookmark.url, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bookmark.name).fontWeight(.semibold).lineLimit(1)
                    if bookmark.skipDuplicateCheck && !dimmed { Text("marked").font(DS.secondary).foregroundStyle(.secondary) }
                }
                if showAddress {
                    Text("\(place) · \(bookmark.url)").font(DS.secondary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(place).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // the list stays open (Matt, Nov 8 2026): the main window comes forward beside it
            Button("Show in place") { model.reveal(bookmark: bookmark.id); ReportWindows.frontMain() }.controlSize(.small).fixedSize()
            Button("Edit…") { model.sheet = .editBookmark(bookmark); ReportWindows.frontMain() }.controlSize(.small).fixedSize()
            Button("Delete…") { confirmDelete = true }.controlSize(.small).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8).padding(.leading, 12)
        .opacity(dimmed ? 0.6 : 1)
        .confirmationDialog("Delete the bookmark “\(bookmark.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete") { model.deleteBookmark(bookmark.id) }
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text((bookmark.hasSecret ? "Its secret goes with it. " : "") + "The other bookmark\(showAddress ? "" : "s") at this page \(showAddress ? "stays" : "stay"). This can't be undone.") }
    }

    /// From the Settings window, the main window comes forward to show the row or the editor.
}

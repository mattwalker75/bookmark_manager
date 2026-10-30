// The link check on screen: the sheet with its progress and then its problems (gone / moved / didn't answer),
// and the banner above the list after a scheduled check found something.
import SwiftUI
import BookmarkManagerCore

struct LinkReportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = model.linkProgress { progress(p) }
            else {
                if let note = model.linkNote { Label(note, systemImage: "wifi.exclamationmark").font(DS.secondary).foregroundStyle(Theme.attention) }
                if let r = model.linkReport { report(r) }
                else if model.linkNote == nil { Text("No check has run yet.").foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if model.linkCheckRunning { Button("Stop") { model.cancelLinkCheck() } }
                else { Button("Check again") { model.checkLinks(inMainWindow: false) } }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 760, height: 580)
    }

    private func progress(_ p: LinkCheckProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checking \(p.total) address\(p.total == 1 ? "" : "es")…").font(DS.heading)
            ProgressView(value: Double(p.done), total: Double(max(1, p.total)))
            Text("\(p.done) done. Each address is asked for once, a few at a time, with this Mac's connection.").font(DS.secondary).foregroundStyle(.secondary)
        }
    }

    private func report(_ r: LinkReport) -> some View {
        let problems = r.problems.sorted { a, b in
            if a.verdict.group != b.verdict.group { return a.verdict.group < b.verdict.group }
            return name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: problems.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(problems.isEmpty ? Theme.good : Theme.attention)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.summary).font(DS.heading)
                    Text(detail(r)).font(DS.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if problems.isEmpty {
                Text("Nothing to do.").foregroundStyle(.secondary)
            } else {
                GroupedCard {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(problems.enumerated()), id: \.element.id) { i, p in
                                if i > 0 { RowDivider(inset: 36) }
                                row(p)
                            }
                        }
                    }
                }
                HStack(spacing: 16) {
                    legend(Theme.problem, "gone — probably needs fixing")
                    legend(Theme.accent, "moved — one click takes the new address")
                    legend(Theme.attention, "didn't answer — maybe just not from this network, or a login page")
                }
                .font(DS.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View { HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(t) } }

    private func detail(_ r: LinkReport) -> String {
        var s = "Checked \(r.checkedAt.formatted(date: .abbreviated, time: .shortened))"
        if r.seconds >= 1 { s += " in \(Int(r.seconds.rounded())) seconds" }
        if let scope = r.scope { s += " · \(scope)" }
        s += " · \(r.checked - r.problems.count) fine · \(r.problems.count) problem\(r.problems.count == 1 ? "" : "s")."
        s += " A site that needs a login or turns robots away can show up here and still work in your browser."
        return s
    }

    private func name(_ p: LinkResult) -> String { model.library.bookmark(p.bookmarkId)?.name ?? "(deleted since)" }
    private func color(_ g: LinkVerdict.Group) -> Color { switch g { case .gone: return Theme.problem; case .moved: return Theme.accent; case .quiet: return Theme.attention } }

    private func row(_ p: LinkResult) -> some View {
        let b = model.library.bookmark(p.bookmarkId)
        let stale = b.map { $0.url != p.url } ?? false   // the address was edited since: nothing to act on
        let place = b.flatMap { model.library.location(ofBookmark: $0.id) }.map { model.placeName($0) } ?? ""
        return HStack(alignment: .center, spacing: 12) {
            Circle().fill(color(p.verdict.group)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(p)).fontWeight(.semibold).lineLimit(1)
                Text(place.isEmpty ? p.url : "\(place) · \(p.url)" + movedSuffix(p)).font(DS.secondary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if stale { Text("address changed since").font(DS.secondary).foregroundStyle(.secondary) }
            Text(p.verdict.text).font(DS.secondary).foregroundStyle(color(p.verdict.group))
                .padding(.horizontal, 8).padding(.vertical, 2).background(color(p.verdict.group).opacity(0.14), in: Capsule())
            if b != nil {
                if case .moved = p.verdict, !stale { Button("Use new address") { model.useNewAddress(p) }.controlSize(.small) }
                Button("Show in place") { dismiss(); model.reveal(bookmark: p.bookmarkId); front() }.controlSize(.small)
                Button("Edit…") { dismiss(); if let b { model.sheet = .editBookmark(b) }; front() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func movedSuffix(_ p: LinkResult) -> String { if case .moved(let to) = p.verdict { return " → \(to)" }; return "" }
    /// From the Settings window, the main window comes forward to show the row.
    private func front() { NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
}

/// Above the list after a scheduled check: "3 addresses didn't answer when checked on Monday — Show".
struct LinkBanner: View {
    @EnvironmentObject var model: AppModel
    let report: LinkReport
    var body: some View {
        let n = model.linkProblems.count
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.attention)
            Text("\(n) address\(n == 1 ? "" : "es") didn't answer as expected when checked \(report.checkedAt.formatted(.relative(presentation: .named))).").lineLimit(1)
            Button("Show") { model.sheet = .linkReport; model.dismissLinkBanner() }.controlSize(.small)
            Spacer()
            Button { model.dismissLinkBanner() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Put this away (the marks stay on the rows)").accessibilityLabel("Dismiss")
        }
        .font(DS.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.attention.opacity(0.14))
    }
}

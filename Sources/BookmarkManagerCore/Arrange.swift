// Moving things: a bookmark or a directory dragged (or sent with Move to…) into another directory, another tab's
// top level, or to another place in the same list. One function holds the rules — the window only reports drops.
import Foundation

/// What a drag carries (as a plain string, so SwiftUI's drag and drop can pass it).
public enum DragItem: Hashable, Sendable {
    case bookmark(UUID)
    case folder(UUID)

    public var token: String {
        switch self { case .bookmark(let id): return "bookmark:\(id.uuidString)"; case .folder(let id): return "folder:\(id.uuidString)" }
    }
    public init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] { case "bookmark": self = .bookmark(id); case "folder": self = .folder(id); default: return nil }
    }
    public var id: UUID { switch self { case .bookmark(let id), .folder(let id): return id } }
}

extension Library {
    /// Moves a bookmark or a directory into the folder at `dest`: at the end, or just before the bookmark /
    /// directory `before` (one of the same kind, in that folder). Refused with a plain reason when it can't be done:
    /// a tab into a directory, a directory into itself, or deeper than the library allows.
    public mutating func move(_ item: DragItem, to dest: FolderPath, before: UUID? = nil) throws {
        guard folder(at: dest) != nil else { throw BMError("The directory it was going into is gone.") }
        if before == item.id { return }
        switch item {
        case .bookmark(let id):
            guard let from = location(ofBookmark: id), let b = bookmark(id) else { throw BMError("That bookmark is gone.") }
            modify(at: from) { $0.bookmarks.removeAll { $0.id == id } }
            modify(at: dest) { f in
                if let before, let i = f.bookmarks.firstIndex(where: { $0.id == before }) { f.bookmarks.insert(b, at: i) } else { f.bookmarks.append(b) }
            }
        case .folder(let id):
            guard let p = path(toFolder: id), let f = folder(at: p) else { throw BMError("That directory is gone.") }
            guard !p.isTabRoot else { throw BMError("A tab can't go inside a directory. Drag tabs along the tab bar to reorder them.") }
            guard !dest.isInside(p) else { throw BMError("“\(f.name)” can't be moved into itself.") }
            let level = dest.depth + 1 + f.levelsBelow
            guard level <= maxDepth else {
                throw BMError(f.levelsBelow == 0
                    ? "“\(f.name)” can't go there: it would be \(level) levels deep and directories may go \(maxDepth) level\(maxDepth == 1 ? "" : "s") deep (Settings → General)."
                    : "“\(f.name)” can't go there: with the directories inside it, it would reach \(level) levels deep and directories may go \(maxDepth) level\(maxDepth == 1 ? "" : "s") deep (Settings → General).")
            }
            modify(at: p.parent!) { $0.folders.removeAll { $0.id == id } }
            modify(at: dest) { d in
                if let before, let i = d.folders.firstIndex(where: { $0.id == before }) { d.folders.insert(f, at: i) } else { d.folders.append(f) }
            }
        }
    }

    /// Can `item` be dropped on `dest` at all? (For the window to light up a target only when a drop would work.)
    public func canMove(_ item: DragItem, to dest: FolderPath) -> Bool {
        var copy = self
        return (try? copy.move(item, to: dest)) != nil
    }
}

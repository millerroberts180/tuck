import SwiftUI
import TuckCore

/// The stream as tiles, each kind in its own face: in the shallow fold one row that scrolls sideways
/// through all of it, in the full fold that row back at its start with the rest in rows under it, so
/// deepening the fold only adds rows under the first. An app's windows, a text being edited and a
/// stack's files open full width under their row, or under the strip.
struct StreamTiles: View {
    @ObservedObject var model: TuckModel
    let stream: [StreamEntry]

    var body: some View {
        TileGrid(items: stream, openIDs: Set(stream.filter(isOpen).map(\.id)),
                 strip: model.foldDepth == .full ? .leads : .scrolls, cursor: model.tileCursor) { entry in
            switch entry {
            case .windows(let group):
                WindowGroupTile(model: model, group: group)
                    // Windows still on their way up keep their tile's place empty until they land in it.
                    .opacity(group.windows.allSatisfy { model.arrivingWindowIDs.contains($0.id) } ? 0 : 1)
            case .item(let item): HeldTile(model: model, item: item)
            case .copied(let copied): ClipboardTile(model: model, entry: copied)
            }
        } detail: { entry in
            switch entry {
            case .windows(let group):
                if group.isMultiWindow {
                    WindowGroupContents(model: model, group: group)
                } else {
                    PlacementChooserView(model: model)
                }
            case .item(let item):
                if model.editingItemID == item.id {
                    InlineTextEditor(model: model)
                } else {
                    StackContents(model: model, stack: item)
                }
            case .copied:
                EmptyView()
            }
        }
    }

    private func isOpen(_ entry: StreamEntry) -> Bool {
        switch entry {
        case .windows(let group): WindowGroupTile.isOpen(group, in: model)
        case .item(let item): model.editingItemID == item.id || (item.kind == .stack && model.revealedStackID == item.id)
        case .copied: false
        }
    }
}

/// The 20 pt column a row's icon sits in: the window picker's apps, and where a tucked window's card
/// lands on a window's row.
enum StreamIcon {
    static let size: CGFloat = 20
}


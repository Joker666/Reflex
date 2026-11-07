import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A target that the user drags to reorder. Text views do not accept this type,
    /// so a drop on the purpose field still reaches the row.
    static let reflexTarget = UTType(exportedAs: "com.rafi.Reflex.target")
}

struct DragHandle: View {
    let target: BrowserTarget
    let icon: NSImage?
    @Binding var draggedTargetID: UUID?
    @State private var showsOpenHand = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder \(target.name)")
            .onDrag {
                draggedTargetID = target.id
                NSCursor.closedHand.set()
                let payload = Data(target.id.uuidString.utf8)
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.reflexTarget.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(payload, nil)
                    return nil
                }
                return provider
            } preview: {
                preview
            }
            .onHover { isHovering in
                if isHovering, !showsOpenHand {
                    NSCursor.openHand.push()
                    showsOpenHand = true
                } else if !isHovering, showsOpenHand {
                    NSCursor.pop()
                    showsOpenHand = false
                }
            }
            .onDisappear {
                if showsOpenHand {
                    NSCursor.pop()
                    showsOpenHand = false
                }
            }
    }

    /// The pointer carries the target's icon and name, so the user sees what moves.
    private var preview: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(target.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fixedSize()
        // Fixed colors, because the preview does not always render in the window's appearance.
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A place in the target list that accepts a drop. The header of a group and its first
/// row have the same target, so each needs its own area for enter and exit to match.
struct DropSlot: Equatable {
    enum Area { case header, row }

    let area: Area
    let targetID: UUID
}

/// The destination owns the highlight because AppKit always tells it when the pointer
/// leaves or the drag ends. The dragged row gets no such call when a drop fails.
struct TargetDropDelegate: DropDelegate {
    let slot: DropSlot
    @Binding var targets: [BrowserTarget]
    @Binding var draggedTargetID: UUID?
    @Binding var dropSlot: DropSlot?

    func dropEntered(info: DropInfo) {
        dropSlot = slot
    }

    func dropExited(info: DropInfo) {
        if dropSlot == slot {
            dropSlot = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropSlot = nil
        guard let draggedID = draggedTargetID else { return false }
        draggedTargetID = nil
        // Apply the move on drop. A live row move can put the pointer over a different
        // row and immediately reverse a full browser-group move. The move is not animated,
        // because the rows have no background and their text would overlap while they slide.
        targets = targets.movingTarget(draggedID, over: slot.targetID)
        return true
    }
}

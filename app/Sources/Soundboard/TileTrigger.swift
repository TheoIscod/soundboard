import AppKit
import SoundboardCore
import SwiftUI

/// Coordinate space of the grid or list content, used to locate drops while reordering.
enum BoardSpace {
  static let name = "board"
}

extension View {
  /// Clicking plays the tile on mouse-up, as in Farrago; Hold to Play tiles start on mouse-down
  /// and stop on mouse-up. Moving more than a few points before releasing drags the tile
  /// instead: `dragOffset` follows the pointer and `onDrop` gets the release point in
  /// `BoardSpace`. Shared by grid tiles and list rows.
  func tileTrigger(
    _ tile: Tile,
    model: BoardModel,
    isPressed: Binding<Bool>,
    dragOffset: Binding<CGSize>,
    onDrop: @escaping (CGPoint) -> Void
  ) -> some View {
    modifier(
      TileTriggerModifier(
        tile: tile,
        model: model,
        isPressed: isPressed,
        dragOffset: dragOffset,
        onDrop: onDrop
      )
    )
  }
}

private struct TileTriggerModifier: ViewModifier {
  /// Pointer travel, in points, that turns a click into a drag.
  static let dragThreshold: CGFloat = 5

  let tile: Tile
  let model: BoardModel
  @Binding var isPressed: Bool
  @Binding var dragOffset: CGSize
  let onDrop: (CGPoint) -> Void

  @State private var isDragging = false
  @State private var startedOnPress = false
  @State private var triggerModifier = TriggerModifier.none

  func body(content: Content) -> some View {
    content.gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardSpace.name))
        .onChanged { value in
          if !isPressed {
            isPressed = true
            triggerModifier = currentTriggerModifier()
            startedOnPress = model.startsOnPress(tile)
            if startedOnPress { model.press(tile, modifier: triggerModifier) }
          }
          let distance = hypot(value.translation.width, value.translation.height)
          if isDragging || distance > Self.dragThreshold {
            isDragging = true
            dragOffset = value.translation
          }
        }
        .onEnded { value in
          if isDragging {
            onDrop(value.location)
          } else if !startedOnPress {
            model.press(tile, modifier: triggerModifier)
          }
          if startedOnPress { model.release(tile) }
          isPressed = false
          isDragging = false
          dragOffset = .zero
        }
    )
  }
}

private func currentTriggerModifier() -> TriggerModifier {
  let flags = NSEvent.modifierFlags
  if flags.contains(.shift) { return .pause }
  if flags.contains(.command) { return .fade }
  return .none
}

/// Context menu shared by grid tiles and list rows.
struct TileContextMenu: View {
  let tile: Tile
  let model: BoardModel
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button("Modifier…", action: onEdit)
    Divider()
    Toggle("Boucle", isOn: model.binding(for: tile, \.player.loops))
    Toggle("Solo", isOn: model.binding(for: tile, \.solo))
    Toggle("Maintenir pour jouer", isOn: model.binding(for: tile, \.holdToPlay))
    Toggle("Activée", isOn: model.binding(for: tile, \.isEnabled))
    Picker("Couleur", selection: model.binding(for: tile, \.color)) {
      ForEach(TileColor.allCases, id: \.self) { color in
        Text(color.displayName).tag(color)
      }
    }
    Divider()
    Button("Supprimer…", role: .destructive, action: onDelete)
  }
}

/// Speaker or pause symbol for a sounding tile, nothing when idle.
struct VoiceStateIndicator: View {
  let state: VoiceState?

  var body: some View {
    switch state {
    case .playing: Image(systemName: "speaker.wave.2.fill")
    case .paused: Image(systemName: "pause.fill")
    case nil: EmptyView()
    }
  }
}

/// The tile's hotkey, shown on the tile and in its list row.
struct HotkeyBadge: View {
  let key: String

  var body: some View {
    Text(key.uppercased())
      .font(.caption.monospaced().bold())
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
      .foregroundStyle(.white)
  }
}

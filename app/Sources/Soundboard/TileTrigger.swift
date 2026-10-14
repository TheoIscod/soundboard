import AppKit
import SoundboardCore
import SwiftUI

extension View {
  /// Plays the tile on mouse-down and reports mouse-up, so Hold to Play can start and stop.
  /// Shared by grid tiles and list rows.
  func tileTrigger(_ tile: Tile, model: BoardModel, isPressed: Binding<Bool>) -> some View {
    gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard !isPressed.wrappedValue else { return }
          isPressed.wrappedValue = true
          model.press(tile, modifier: currentTriggerModifier())
        }
        .onEnded { _ in
          isPressed.wrappedValue = false
          model.release(tile)
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
    Button("Edit…", action: onEdit)
    Divider()
    Toggle("Loop", isOn: model.binding(for: tile, \.player.loops))
    Toggle("Solo", isOn: model.binding(for: tile, \.solo))
    Toggle("Hold to Play", isOn: model.binding(for: tile, \.holdToPlay))
    Toggle("Enabled", isOn: model.binding(for: tile, \.isEnabled))
    Picker("Color", selection: model.binding(for: tile, \.color)) {
      ForEach(TileColor.allCases, id: \.self) { color in
        Text(color.displayName).tag(color)
      }
    }
    Divider()
    Button("Delete…", role: .destructive, action: onDelete)
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

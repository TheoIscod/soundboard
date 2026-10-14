import SoundboardCore
import SwiftUI

struct TileView: View {
  let tile: Tile
  let state: VoiceState?
  let isSelected: Bool
  let model: BoardModel
  let onEdit: () -> Void
  let onDelete: () -> Void

  @State private var isPressed = false

  var body: some View {
    VStack(spacing: 6) {
      if !tile.icon.isEmpty {
        Text(tile.icon).font(.largeTitle)
      }
      Text(tile.title)
        .font(.headline)
        .lineLimit(2)
        .multilineTextAlignment(.center)
      badges
    }
    .foregroundStyle(.white)
    .padding(8)
    .frame(maxWidth: .infinity, minHeight: 96)
    .background(tile.color.swiftUIColor.opacity(tile.isEnabled ? 1 : 0.35))
    .overlay(alignment: .topTrailing) { VoiceStateIndicator(state: state).padding(6) }
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(.white, lineWidth: state == .playing ? 3 : 0)
    }
    .padding(3)
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
    }
    .scaleEffect(isPressed ? 0.96 : 1)
    .animation(.easeOut(duration: 0.1), value: isPressed)
    .tileTrigger(tile, model: model, isPressed: $isPressed)
    .contextMenu {
      TileContextMenu(tile: tile, model: model, onEdit: onEdit, onDelete: onDelete)
    }
    .help("Click: play/stop · ⇧-click: pause · ⌘-click: fade out")
  }

  private var badges: some View {
    HStack(spacing: 4) {
      if tile.player.loops { Image(systemName: "repeat") }
      if tile.solo { Image(systemName: "s.circle.fill") }
      if tile.holdToPlay { Image(systemName: "hand.point.up.left.fill") }
    }
    .font(.caption)
  }
}

extension TileColor {
  var swiftUIColor: Color {
    switch self {
    case .purple: .purple
    case .pink: .pink
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .lightBlue: .cyan
    case .darkBlue: .blue
    case .black: Color(white: 0.15)
    }
  }

  var displayName: String {
    switch self {
    case .lightBlue: "Light Blue"
    case .darkBlue: "Dark Blue"
    default: String(describing: self).capitalized
    }
  }
}

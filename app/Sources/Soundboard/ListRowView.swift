import SoundboardCore
import SwiftUI

/// One tile as a list-mode row: position, icon, title, length and played mark.
struct ListRowView: View {
  let tile: Tile
  let number: Int
  let state: VoiceState?
  let isSelected: Bool
  let model: BoardModel
  let onEdit: () -> Void
  let onDelete: () -> Void
  /// Release point, in `BoardSpace`, of a drag that moves this tile.
  let onDrop: (CGPoint) -> Void

  @State private var isPressed = false
  @State private var dragOffset = CGSize.zero

  var body: some View {
    HStack(spacing: 10) {
      Text("\(number)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 28, alignment: .trailing)
      RoundedRectangle(cornerRadius: 2)
        .fill(tile.color.swiftUIColor)
        .frame(width: 4, height: 22)
      Text(tile.icon.isEmpty ? " " : tile.icon)
        .frame(width: 24)
      Text(tile.title)
        .lineLimit(1)
        .strikethrough(!tile.isEnabled)
      Spacer()
      if tile.player.loops {
        Image(systemName: "repeat").foregroundStyle(.secondary)
      }
      if let hotkey = tile.hotkey { HotkeyBadge(key: hotkey) }
      VoiceStateIndicator(state: state)
        .foregroundStyle(Color.accentColor)
        .frame(width: 18)
      Text(playLength)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .trailing)
      Image(systemName: tile.lastPlayed == nil ? "circle" : "checkmark.circle.fill")
        .foregroundStyle(tile.lastPlayed == nil ? Color.secondary : Color.green)
        .help(tile.lastPlayed == nil ? "Pas encore joué" : "Déjà joué")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    .opacity(tile.lastPlayed == nil ? 1 : 0.6)
    .contentShape(Rectangle())
    .tileTrigger(
      tile,
      model: model,
      isPressed: $isPressed,
      dragOffset: $dragOffset,
      onDrop: onDrop
    )
    .offset(dragOffset)
    .zIndex(dragOffset == .zero ? 0 : 1)
    .opacity(dragOffset == .zero ? 1 : 0.85)
    .contextMenu {
      TileContextMenu(tile: tile, model: model, onEdit: onEdit, onDelete: onDelete)
    }
  }

  private var rowBackground: Color {
    if isSelected { return Color.accentColor.opacity(0.25) }
    if state == .playing { return Color.accentColor.opacity(0.12) }
    return isPressed ? Color.primary.opacity(0.08) : .clear
  }

  /// Length once trimmed, as m:ss.
  private var playLength: String {
    guard let duration = model.duration(of: tile) else { return "–:––" }
    let seconds = Int(max(duration - tile.player.trimStart - tile.player.trimEnd, 0).rounded())
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
  }
}

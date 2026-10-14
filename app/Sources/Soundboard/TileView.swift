import AppKit
import SoundboardCore
import SwiftUI

struct TileView: View {
  let tile: Tile
  let state: VoiceState?
  let model: BoardModel

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
    .overlay(alignment: .topTrailing) { stateIndicator.padding(6) }
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(.white, lineWidth: state == .playing ? 3 : 0)
    }
    .scaleEffect(isPressed ? 0.96 : 1)
    .animation(.easeOut(duration: 0.1), value: isPressed)
    .gesture(pressGesture)
    .contextMenu { contextMenu }
    .help("Click: play/stop · ⇧-click: pause · ⌘-click: fade out")
  }

  /// Fires on mouse-down and mouse-up so Hold to Play tiles can start and stop.
  private var pressGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { _ in
        guard !isPressed else { return }
        isPressed = true
        model.press(tile, modifier: currentModifier())
      }
      .onEnded { _ in
        isPressed = false
        model.release(tile)
      }
  }

  private func currentModifier() -> TriggerModifier {
    let flags = NSEvent.modifierFlags
    if flags.contains(.shift) { return .pause }
    if flags.contains(.command) { return .fade }
    return .none
  }

  @ViewBuilder
  private var stateIndicator: some View {
    switch state {
    case .playing: Image(systemName: "speaker.wave.2.fill")
    case .paused: Image(systemName: "pause.fill")
    case nil: EmptyView()
    }
  }

  private var badges: some View {
    HStack(spacing: 4) {
      if tile.player.loops { Image(systemName: "repeat") }
      if tile.solo { Image(systemName: "s.circle.fill") }
      if tile.holdToPlay { Image(systemName: "hand.point.up.left.fill") }
    }
    .font(.caption)
  }

  @ViewBuilder
  private var contextMenu: some View {
    Toggle("Loop", isOn: binding(\.player.loops))
    Toggle("Solo", isOn: binding(\.solo))
    Toggle("Hold to Play", isOn: binding(\.holdToPlay))
    Toggle("Enabled", isOn: binding(\.isEnabled))
    Picker("Color", selection: binding(\.color)) {
      ForEach(TileColor.allCases, id: \.self) { color in
        Text(color.displayName).tag(color)
      }
    }
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<Tile, Value>) -> Binding<Value> {
    Binding(
      get: { tile[keyPath: keyPath] },
      set: { newValue in
        var updated = tile
        updated[keyPath: keyPath] = newValue
        model.update(updated)
      }
    )
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

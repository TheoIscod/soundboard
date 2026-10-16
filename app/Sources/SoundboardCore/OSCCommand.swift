import Foundation

/// What an OSC message asks the board to do. Addresses follow the scheme found in Farrago's
/// binary (`/set/<n>/tile/<x>/<y>/…`, `/master/…`, `/transport/…`); the exact action list
/// per tile is partly inferred, see analysis/notes/00-feature-map.md.
public enum OSCCommand: Sendable, Equatable {
  public enum SetReference: Sendable, Equatable {
    /// Position in the sidebar, from 0.
    case index(Int)
    /// The set shown in the window.
    case selected
  }

  public enum TileAction: String, Sendable, CaseIterable {
    case play, fade, loop, mute, solo, toggleAB
  }

  /// `pressed` is false for the release of a button (value 0), which only matters to `play`
  /// on Hold to Play tiles; other actions ignore releases.
  case tile(SetReference, GridPosition, TileAction, pressed: Bool)
  case masterToggleAB
  case masterSelectVolumeA
  case masterSelectVolumeB
  case masterVolumeUp
  case masterVolumeDown
  /// 0…1, clamped.
  case masterVolume(Float)
  case playPauseAll
  case stopAll

  public init?(_ message: OSCMessage) {
    let parts = message.address.split(separator: "/", omittingEmptySubsequences: true)
    let value = message.arguments.first?.number
    // Buttons send 1 when pressed and 0 when released; a message without a value is a press.
    let pressed = (value ?? 1) != 0

    let path = parts.map(String.init)

    if path.count == 6, path[0] == "set", path[2] == "tile" {
      guard let reference = Self.setReference(path[1]),
        let column = Int(path[3]), let row = Int(path[4]), column >= 0, row >= 0,
        let action = TileAction(rawValue: path[5])
      else { return nil }
      self = .tile(reference, GridPosition(column: column, row: row), action, pressed: pressed)
      return
    }

    switch path.joined(separator: "/") {
    case "master/volume":
      guard let value else { return nil }
      self = .masterVolume(Float(min(max(value, 0), 1)))
    case "master/toggleAB" where pressed: self = .masterToggleAB
    case "master/selectVolumeA" where pressed: self = .masterSelectVolumeA
    case "master/selectVolumeB" where pressed: self = .masterSelectVolumeB
    case "master/volumeUp" where pressed: self = .masterVolumeUp
    case "master/volumeDown" where pressed: self = .masterVolumeDown
    case "transport/playPauseAll" where pressed: self = .playPauseAll
    case "transport/stopAll" where pressed: self = .stopAll
    default: return nil
    }
  }

  private static func setReference(_ text: String) -> SetReference? {
    if text == "selected" { return .selected }
    guard let index = Int(text), index >= 0 else { return nil }
    return .index(index)
  }

  /// Feedback telling a controller whether a tile plays, e.g. to light its button.
  public static func playingFeedback(setIndex: Int, position: GridPosition, isPlaying: Bool)
    -> OSCMessage
  {
    OSCMessage(
      address: "/set/\(setIndex)/tile/\(position.column)/\(position.row)/play",
      arguments: [.float(isPlaying ? 1 : 0)]
    )
  }
}

extension SoundSet {
  public func tile(at position: GridPosition) -> Tile? {
    tiles.first { $0.gridPosition == position }
  }
}

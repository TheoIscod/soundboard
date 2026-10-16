import Foundation

/// A key that plays a tile of the shown set: one letter or digit, stored lowercased.
public enum Hotkey {
  /// Keys already used by app-wide playback shortcuts (Pause All, Fade Out All).
  public static let reserved: Set<Character> = [" ", "-"]

  /// The hotkey for typed text, or nil if it isn't a single assignable letter or digit.
  public static func normalized(_ text: String) -> String? {
    let lowered = text.lowercased()
    guard lowered.count == 1, let character = lowered.first,
      character.isASCII, character.isLetter || character.isNumber,
      !reserved.contains(character)
    else { return nil }
    return lowered
  }
}

extension SoundSet {
  public func tile(forHotkey key: String) -> Tile? {
    guard let key = Hotkey.normalized(key) else { return nil }
    return tiles.first { $0.hotkey == key }
  }

  /// Gives `key` to one tile, taking it away from any other tile of the set;
  /// nil or an invalid key clears the tile's hotkey.
  public mutating func assignHotkey(_ key: String?, to tileID: UUID) {
    let key = key.flatMap(Hotkey.normalized)
    for index in tiles.indices {
      if tiles[index].id == tileID {
        tiles[index].hotkey = key
      } else if key != nil, tiles[index].hotkey == key {
        tiles[index].hotkey = nil
      }
    }
  }
}

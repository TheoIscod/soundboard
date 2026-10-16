import Foundation

/// Rules that make a set smart: it shows the tiles of ordinary sets that match them
/// (see analysis/notes/03-smart-sets.md).
public struct SmartRules: Codable, Sendable, Equatable {
  public enum Match: String, Codable, Sendable, CaseIterable {
    /// Every rule must match.
    case all
    /// At least one rule must match.
    case any
  }

  public var match: Match
  public var rules: [SmartRule]

  public init(match: Match = .all, rules: [SmartRule] = [.flag(.favorite, is: true)]) {
    self.match = match
    self.rules = rules
  }

  /// A smart set without rules matches nothing, rather than every tile.
  public func matches(_ tile: Tile) -> Bool {
    guard !rules.isEmpty else { return false }
    switch match {
    case .all: return rules.allSatisfy { $0.matches(tile) }
    case .any: return rules.contains { $0.matches(tile) }
    }
  }
}

public enum SmartRule: Codable, Sendable, Equatable {
  public enum TextComparison: String, Codable, Sendable, CaseIterable {
    case contains, beginsWith, endsWith
  }

  public enum Flag: String, Codable, Sendable, CaseIterable {
    case favorite, loops, holdToPlay, solo, played
  }

  case title(TextComparison, String)
  case color(TileColor)
  case flag(Flag, is: Bool)

  public func matches(_ tile: Tile) -> Bool {
    switch self {
    case .title(let comparison, let text):
      let text = text.trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { return false }
      let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
      switch comparison {
      case .contains: return tile.title.range(of: text, options: options) != nil
      case .beginsWith: return tile.title.range(of: text, options: options.union(.anchored)) != nil
      case .endsWith:
        return tile.title.range(of: text, options: options.union([.anchored, .backwards])) != nil
      }
    case .color(let color):
      return tile.color == color
    case .flag(let flag, let expected):
      let value =
        switch flag {
        case .favorite: tile.isFavorite
        case .loops: tile.player.loops
        case .holdToPlay: tile.holdToPlay
        case .solo: tile.solo
        case .played: tile.lastPlayed != nil
        }
      return value == expected
    }
  }
}

extension SoundSet {
  public var isSmart: Bool { smartRules != nil }
}

extension SoundLibrary {
  /// What a set shows: its own tiles, or for a smart set the matching tiles of the ordinary
  /// sets, in sidebar order then each set's grid order, laid out in a fresh grid.
  public func shownSet(_ set: SoundSet, gridColumns: Int) -> SoundSet {
    guard let rules = set.smartRules else { return set }
    var shown = set
    let matching = sets.filter { !$0.isSmart }.flatMap { $0.gridOrder.filter(rules.matches) }
    shown.tiles = matching.enumerated().map { index, tile in
      var placed = tile
      placed.gridPosition = GridPosition(column: index % gridColumns, row: index / gridColumns)
      placed.listIndex = index
      return placed
    }
    return shown
  }
}

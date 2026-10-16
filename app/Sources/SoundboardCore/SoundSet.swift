import Foundation

/// What happens when a tile finishes playing (see analysis/notes/02-playback-behaviour.md).
public enum PlaybackMode: Int, Codable, Sendable, CaseIterable {
  /// Nothing happens.
  case single = 0
  /// The next playable tile is cued (selected) but not started.
  case toggle = 1
  /// The next playable tile starts automatically, crossfading into it.
  case continuous = 2
}

public enum DisplayMode: Int, Codable, Sendable {
  case grid = 0
  case list = 1
}

public enum TileColor: Int, Codable, Sendable, CaseIterable {
  case purple, pink, red, orange, yellow, green, lightBlue, darkBlue, black
}

public struct PlayerSettings: Codable, Sendable, Equatable {
  /// Trim, in seconds from the start and from the end of the file.
  /// Seconds rather than codec packets so the model is codec-independent.
  public var trimStart: TimeInterval = 0
  public var trimEnd: TimeInterval = 0
  public var fadeInTime: TimeInterval = 0
  public var fadeOutTime: TimeInterval = 0
  public var loops = false
  public var pausable = false
  public var volumeA: Float = 1.0
  public var volumeB: Float = 0.4
  /// When true the tile plays at `volumeB`.
  public var usesVolumeB = false
  public var muted = false

  public init() {}

  public var activeVolume: Float { usesVolumeB ? volumeB : volumeA }
}

public struct Tile: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  /// Audio file stored inside the set package.
  public var fileID: UUID
  public var originalFileName: String
  public var title: String
  public var icon = ""
  public var notes = ""
  public var color = TileColor.purple
  public var isEnabled = true
  public var holdToPlay = false
  public var solo = false
  public var isFavorite = false
  public var lastPlayed: Date?
  public var gridPosition = GridPosition(column: 0, row: 0)
  public var listIndex = 0
  public var player = PlayerSettings()

  public init(fileID: UUID, originalFileName: String, title: String) {
    self.fileID = fileID
    self.originalFileName = originalFileName
    self.title = title
  }
}

public struct GridPosition: Codable, Sendable, Equatable, Hashable {
  public var column: Int
  public var row: Int

  public init(column: Int, row: Int) {
    self.column = column
    self.row = row
  }
}

public struct SoundSet: Codable, Sendable, Equatable, Identifiable {
  /// Bumped whenever the on-disk shape changes incompatibly.
  public static let formatVersion = 1

  public var formatVersion = SoundSet.formatVersion
  public var id = UUID()
  public var title: String
  public var notes = ""
  public var displayMode = DisplayMode.grid
  public var playbackMode = PlaybackMode.toggle
  public var crossfadeDuration: TimeInterval = 0
  public var isLocked = false
  public var tiles: [Tile] = []

  public init(title: String) {
    self.title = title
  }

  /// Tiles in the grid's reading order.
  public var gridOrder: [Tile] {
    tiles.sorted {
      ($0.gridPosition.row, $0.gridPosition.column) < ($1.gridPosition.row, $1.gridPosition.column)
    }
  }

  /// Tiles in list order; equal indices (tiles added before list order was kept) follow the grid.
  public var listOrder: [Tile] {
    tiles.sorted {
      ($0.listIndex, $0.gridPosition.row, $0.gridPosition.column)
        < ($1.listIndex, $1.gridPosition.row, $1.gridPosition.column)
    }
  }

  public var displayOrder: [Tile] {
    displayMode == .list ? listOrder : gridOrder
  }

  /// List index for a tile added at the end of the list.
  public var nextListIndex: Int {
    (tiles.map(\.listIndex).max() ?? -1) + 1
  }

  public var firstPlayableTile: Tile? {
    displayOrder.first { $0.isEnabled }
  }

  /// The next enabled tile after `tileID` in display order; the list does not wrap around.
  public func nextPlayableTile(after tileID: UUID) -> Tile? {
    let order = displayOrder
    guard let index = order.firstIndex(where: { $0.id == tileID }) else { return nil }
    return order[(index + 1)...].first { $0.isEnabled }
  }

  /// The crossfade setting while Continuous is active, nil otherwise.
  /// Advance modes only act in list mode; a grid never advances on its own.
  public var continuousCrossfade: TimeInterval? {
    displayMode == .list && playbackMode == .continuous ? crossfadeDuration : nil
  }

  /// Tile to select after `tileID` stops, in Cue next mode.
  public func tileToCue(afterStopping tileID: UUID) -> Tile? {
    guard displayMode == .list, playbackMode == .toggle else { return nil }
    return nextPlayableTile(after: tileID)
  }

  /// How long before the end of a sound Continuous starts the next one and crossfades:
  /// the set's crossfade, but never more than half the sound.
  public static func crossfadeLead(crossfade: TimeInterval, soundLength: TimeInterval)
    -> TimeInterval
  {
    min(max(crossfade, 0), max(soundLength, 0) / 2)
  }

  /// Moves a tile to `index` in the current display order and renumbers that order only:
  /// list moves rewrite list indices, grid moves rewrite grid cells (packing any gaps).
  public mutating func moveTile(_ tileID: UUID, to index: Int, gridColumns: Int) {
    var order = displayOrder
    guard let from = order.firstIndex(where: { $0.id == tileID }) else { return }
    let moved = order.remove(at: from)
    order.insert(moved, at: min(max(index, 0), order.count))

    let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.id, $0) })
    for tileIndex in tiles.indices {
      guard let position = positions[tiles[tileIndex].id] else { continue }
      switch displayMode {
      case .list:
        tiles[tileIndex].listIndex = position
      case .grid:
        tiles[tileIndex].gridPosition = GridPosition(
          column: position % gridColumns,
          row: position / gridColumns
        )
      }
    }
  }

  /// First empty cell in reading order, so deleted tiles leave a gap that new tiles fill.
  public func nextFreeGridPosition(columns: Int) -> GridPosition {
    let taken = Set(tiles.map(\.gridPosition))
    var index = 0
    while true {
      let position = GridPosition(column: index % columns, row: index / columns)
      if !taken.contains(position) { return position }
      index += 1
    }
  }
}

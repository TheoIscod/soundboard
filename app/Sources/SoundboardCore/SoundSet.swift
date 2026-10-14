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
}

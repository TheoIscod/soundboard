import Foundation

public enum VoiceState: Sendable, Equatable {
  case playing
  case paused
}

/// Modifier held while triggering a tile.
public enum TriggerModifier: Sendable, Equatable {
  case none
  /// Pause a playing tile instead of stopping it.
  case pause
  /// Fade out instead of cutting: applies to the tile itself and to sounds a solo tile stops.
  case fade
}

public enum PlaybackCommand: Sendable, Equatable {
  case start(UUID)
  /// `fade == nil` stops immediately.
  case stop(UUID, fade: TimeInterval?)
  case pause(UUID)
  case resume(UUID)
}

/// Decides what happens when tiles are triggered; the audio engine only executes the commands.
public struct PlaybackCoordinator: Sendable {
  public private(set) var states: [UUID: VoiceState] = [:]
  /// Global fade time preference, used for faded stops and Fade Out All.
  public var fadeTime: TimeInterval = 2.0

  public init() {}

  public func state(of tileID: UUID) -> VoiceState? { states[tileID] }

  /// Mouse-down / key-down on a tile.
  public mutating func press(_ tile: Tile, modifier: TriggerModifier = .none)
    -> [PlaybackCommand]
  {
    guard tile.isEnabled else { return [] }
    if tile.holdToPlay {
      return states[tile.id] == nil ? start(tile, modifier: modifier) : []
    }

    switch (states[tile.id], modifier) {
    case (nil, _):
      return start(tile, modifier: modifier)
    case (.playing, .pause):
      states[tile.id] = .paused
      return [.pause(tile.id)]
    case (.playing, .fade):
      states[tile.id] = nil
      return [.stop(tile.id, fade: fadeTime)]
    case (.playing, .none):
      states[tile.id] = nil
      return [.stop(tile.id, fade: nil)]
    case (.paused, _):
      states[tile.id] = .playing
      return [.resume(tile.id)]
    }
  }

  /// Mouse-up / key-up on a tile: only Hold to Play tiles react.
  public mutating func release(_ tile: Tile) -> [PlaybackCommand] {
    guard tile.holdToPlay, states[tile.id] != nil else { return [] }
    states[tile.id] = nil
    return [.stop(tile.id, fade: nil)]
  }

  /// The engine reports that a voice ended on its own (end of file or faded to silence).
  public mutating func voiceDidFinish(_ tileID: UUID) {
    states[tileID] = nil
  }

  public mutating func stopAll() -> [PlaybackCommand] {
    stopEverything(except: nil, fade: nil)
  }

  public mutating func fadeOutAll() -> [PlaybackCommand] {
    stopEverything(except: nil, fade: fadeTime)
  }

  private mutating func start(_ tile: Tile, modifier: TriggerModifier) -> [PlaybackCommand] {
    var commands: [PlaybackCommand] = []
    if tile.solo {
      commands += stopEverything(except: tile.id, fade: modifier == .fade ? fadeTime : nil)
    }
    states[tile.id] = .playing
    commands.append(.start(tile.id))
    return commands
  }

  private mutating func stopEverything(except kept: UUID?, fade: TimeInterval?)
    -> [PlaybackCommand]
  {
    // Sorted so the command order is deterministic.
    let stopped = states.keys.filter { $0 != kept }.sorted { $0.uuidString < $1.uuidString }
    for id in stopped { states[id] = nil }
    return stopped.map { .stop($0, fade: fade) }
  }
}

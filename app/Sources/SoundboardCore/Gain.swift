import Foundation

/// A gain that moves linearly from its current value to a target over a duration.
/// All live fades and volume changes are linear in gain (see 02-playback-behaviour.md).
public struct LinearRamp: Sendable, Equatable {
  /// Duration used for every volume change (A/B switch, slider, mute, master).
  public static let volumeChangeDuration: TimeInterval = 0.2

  public private(set) var value: Float
  public private(set) var target: Float
  private var origin: Float
  private var duration: TimeInterval = 0
  private var progress: Double = 1

  public init(value: Float) {
    self.value = value
    target = value
    origin = value
  }

  public var isFinished: Bool { progress >= 1 }

  /// Starts moving from the current value, so retargeting mid-ramp never jumps.
  public mutating func move(to target: Float, over duration: TimeInterval) {
    origin = value
    self.target = target
    self.duration = duration
    if duration <= 0 {
      value = target
      progress = 1
    } else {
      progress = 0
    }
  }

  @discardableResult
  public mutating func advance(by elapsed: TimeInterval) -> Float {
    guard progress < 1 else { return value }
    progress = min(1, max(0, progress + elapsed / duration))
    value = progress >= 1 ? target : origin + (target - origin) * Float(progress)
    return value
  }
}

public enum Gain {
  /// Values this close to 0 or 1 are treated as exactly 0 or 1.
  public static let snapTolerance: Float = 1e-5

  public static func snapped(_ gain: Float) -> Float {
    if abs(gain) < snapTolerance { return 0 }
    if abs(gain - 1) < snapTolerance { return 1 }
    return gain
  }

  /// Per-tile fade envelope at `position` seconds into a trimmed region of `length` seconds.
  /// Each fade is limited to half the region so fade-in and fade-out never overlap.
  public static func envelope(
    at position: TimeInterval,
    length: TimeInterval,
    fadeIn: TimeInterval,
    fadeOut: TimeInterval
  ) -> Float {
    guard length > 0 else { return 1 }
    let half = length / 2
    let fadeIn = min(max(fadeIn, 0), half)
    let fadeOut = min(max(fadeOut, 0), half)
    var gain = 1.0
    if fadeIn > 0, position < fadeIn {
      gain = min(gain, max(position, 0) / fadeIn)
    }
    let remaining = length - position
    if fadeOut > 0, remaining < fadeOut {
      gain = min(gain, max(remaining, 0) / fadeOut)
    }
    return Float(gain)
  }
}

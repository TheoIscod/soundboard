import Foundation

/// App-wide output level with two presets, A and B, like each tile's own volumes.
/// Switching between them dims or restores the whole board at once.
public struct MasterVolume: Codable, Sendable, Equatable {
  /// Change applied by Master Volume Up / Down.
  public static let step: Float = 0.05

  public var volumeA: Float = 1.0
  public var volumeB: Float = 0.4
  /// When true the board plays at `volumeB`.
  public var usesVolumeB = false
  public var muted = false

  public init() {}

  /// The preset currently in use; editing it edits A or B.
  public var activeVolume: Float {
    get { usesVolumeB ? volumeB : volumeA }
    set {
      let clamped = min(max(newValue, 0), 1)
      if usesVolumeB { volumeB = clamped } else { volumeA = clamped }
    }
  }

  /// Gain applied to every sound.
  public var gain: Float { muted ? 0 : activeVolume }

  public mutating func toggleAB() {
    usesVolumeB.toggle()
  }

  public mutating func stepUp() {
    activeVolume += Self.step
  }

  public mutating func stepDown() {
    activeVolume -= Self.step
  }
}

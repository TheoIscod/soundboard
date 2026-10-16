import Foundation

/// A span of a sound file, in seconds from its start, always ordered.
public struct TimeRange: Sendable, Equatable {
  public let start: TimeInterval
  public let end: TimeInterval

  /// Accepts the two ends in any order, e.g. from a drag to the left.
  public init(_ first: TimeInterval, _ second: TimeInterval) {
    start = min(first, second)
    end = max(first, second)
  }

  public var length: TimeInterval { end - start }
}

/// The part of a sound the editor shows, for zooming and scrolling.
public struct WaveformViewport: Sendable, Equatable {
  /// Shortest span the editor zooms to.
  public static let minimumLength: TimeInterval = 0.05
  public static let zoomFactor = 2.0

  public let duration: TimeInterval
  public private(set) var visible: TimeRange

  public init(duration: TimeInterval) {
    self.duration = max(duration, 0)
    visible = TimeRange(0, self.duration)
  }

  public mutating func zoomIn() {
    zoom(to: visible.length / Self.zoomFactor, around: (visible.start + visible.end) / 2)
  }

  public mutating func zoomOut() {
    zoom(to: visible.length * Self.zoomFactor, around: (visible.start + visible.end) / 2)
  }

  public mutating func zoomToFit() {
    visible = TimeRange(0, duration)
  }

  public mutating func zoom(to range: TimeRange) {
    zoom(to: range.length, around: (range.start + range.end) / 2)
  }

  /// Moves the visible span by `seconds`, staying inside the sound.
  public mutating func scroll(by seconds: TimeInterval) {
    place(length: visible.length, start: visible.start + seconds)
  }

  /// Seconds into the sound at `x` in a view `width` points wide.
  public func time(atX x: Double, width: Double) -> TimeInterval {
    guard width > 0 else { return visible.start }
    return visible.start + min(max(x / width, 0), 1) * visible.length
  }

  /// Horizontal position of `time` in a view `width` points wide; may fall outside it.
  public func x(of time: TimeInterval, width: Double) -> Double {
    guard visible.length > 0 else { return 0 }
    return (time - visible.start) / visible.length * width
  }

  private mutating func zoom(to length: TimeInterval, around center: TimeInterval) {
    let length = min(max(length, min(Self.minimumLength, duration)), duration)
    place(length: length, start: center - length / 2)
  }

  private mutating func place(length: TimeInterval, start: TimeInterval) {
    let start = min(max(start, 0), duration - length)
    visible = TimeRange(start, start + length)
  }
}

extension TrimEditor {
  /// Keeps only the selection ("Crop Selection"), without touching the sound file.
  public func cropping(to selection: TimeRange, in settings: PlayerSettings) -> PlayerSettings {
    let cropped = settingEnd(selection.end, in: settingStart(selection.start, in: settings))
    return settingStart(selection.start, in: cropped)
  }

  /// Starts the sound at the selection and fades it in over the selection.
  public func fadingIn(over selection: TimeRange, in settings: PlayerSettings) -> PlayerSettings {
    let started = settingStart(selection.start, in: settings)
    return settingFadeInEnd(selection.end, in: started)
  }

  /// Ends the sound at the selection's end and fades it out over the selection.
  public func fadingOut(over selection: TimeRange, in settings: PlayerSettings) -> PlayerSettings {
    let ended = settingEnd(selection.end, in: settings)
    return settingFadeOutStart(selection.start, in: ended)
  }

  /// Removes trim and fades ("Revert to Original"); the sound file was never changed.
  public func reverting(_ settings: PlayerSettings) -> PlayerSettings {
    var settings = settings
    settings.trimStart = 0
    settings.trimEnd = 0
    settings.fadeInTime = 0
    settings.fadeOutTime = 0
    return settings
  }
}

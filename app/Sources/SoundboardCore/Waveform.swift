import Foundation

/// Lowest and highest sample of one slice of a sound, for drawing its waveform.
public struct WaveformPeak: Sendable, Equatable {
  public var low: Float
  public var high: Float

  public init(low: Float, high: Float) {
    self.low = low
    self.high = high
  }
}

public enum Waveform {
  /// Splits mono samples into `binCount` equal slices and keeps each slice's extremes.
  /// Shorter sounds give fewer bins, one per sample.
  public static func peaks(of samples: [Float], binCount: Int) -> [WaveformPeak] {
    guard !samples.isEmpty, binCount > 0 else { return [] }
    let bins = min(binCount, samples.count)
    return (0..<bins).map { bin in
      let start = bin * samples.count / bins
      let end = (bin + 1) * samples.count / bins
      let slice = samples[start..<end]
      return WaveformPeak(low: slice.min() ?? 0, high: slice.max() ?? 0)
    }
  }
}

extension Waveform {
  /// Regroups the peaks covering `fraction` of the sound (0…1 at both ends) into `columns`
  /// slices, keeping extremes, so a long or zoomed waveform draws one bar per pixel column.
  public static func columns(
    of peaks: [WaveformPeak],
    from start: Double,
    to end: Double,
    count columns: Int
  ) -> [WaveformPeak] {
    guard !peaks.isEmpty, columns > 0, end > start else { return [] }
    let first = Double(peaks.count) * min(max(start, 0), 1)
    let span = Double(peaks.count) * min(max(end, 0), 1) - first
    return (0..<columns).map { column in
      let lower = Int(first + span * Double(column) / Double(columns))
      let upper = max(Int(first + span * Double(column + 1) / Double(columns)), lower + 1)
      let slice = peaks[min(lower, peaks.count - 1)..<min(upper, peaks.count)]
      return WaveformPeak(
        low: slice.map(\.low).min() ?? 0,
        high: slice.map(\.high).max() ?? 0
      )
    }
  }
}

/// Mouse edits of a tile's trim and fades on its waveform, keeping them consistent:
/// at least `minimumLength` stays playable and each fade fits in half the playable part.
public struct TrimEditor: Sendable {
  public static let minimumLength: TimeInterval = 0.1

  public let duration: TimeInterval

  public init(duration: TimeInterval) {
    self.duration = duration
  }

  /// Moves the start point to `time` seconds into the file.
  public func settingStart(_ time: TimeInterval, in settings: PlayerSettings) -> PlayerSettings {
    var settings = settings
    let latest = duration - settings.trimEnd - Self.minimumLength
    settings.trimStart = clamp(time, 0, max(latest, 0))
    return fittingFades(settings)
  }

  /// Moves the end point to `time` seconds into the file.
  public func settingEnd(_ time: TimeInterval, in settings: PlayerSettings) -> PlayerSettings {
    var settings = settings
    let earliest = settings.trimStart + Self.minimumLength
    settings.trimEnd = duration - clamp(time, min(earliest, duration), duration)
    return fittingFades(settings)
  }

  /// Ends the fade-in at `time` seconds into the file.
  public func settingFadeInEnd(_ time: TimeInterval, in settings: PlayerSettings)
    -> PlayerSettings
  {
    var settings = settings
    settings.fadeInTime = clamp(time - settings.trimStart, 0, maximumFade(settings))
    return settings
  }

  /// Starts the fade-out at `time` seconds into the file.
  public func settingFadeOutStart(_ time: TimeInterval, in settings: PlayerSettings)
    -> PlayerSettings
  {
    var settings = settings
    settings.fadeOutTime = clamp(end(of: settings) - time, 0, maximumFade(settings))
    return settings
  }

  /// Where playback stops, in seconds into the file.
  public func end(of settings: PlayerSettings) -> TimeInterval {
    duration - settings.trimEnd
  }

  private func maximumFade(_ settings: PlayerSettings) -> TimeInterval {
    max(end(of: settings) - settings.trimStart, 0) / 2
  }

  private func fittingFades(_ settings: PlayerSettings) -> PlayerSettings {
    var settings = settings
    let limit = maximumFade(settings)
    settings.fadeInTime = min(settings.fadeInTime, limit)
    settings.fadeOutTime = min(settings.fadeOutTime, limit)
    return settings
  }

  private func clamp(_ value: TimeInterval, _ low: TimeInterval, _ high: TimeInterval)
    -> TimeInterval
  {
    min(max(value, low), high)
  }
}

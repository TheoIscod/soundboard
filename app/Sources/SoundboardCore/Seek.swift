import Foundation

/// Moving the playback of a sounding tile (Farrago's Scan Backward / Forward).
public enum Seek {
  /// Step of ← / → in the editor; ⇧ uses the fine step. Farrago's own step is not known.
  public static let scanStep: TimeInterval = 5
  public static let fineScanStep: TimeInterval = 1
  /// A sound that isn't looping stops this close to its end rather than at it, so a scan
  /// forward still lets the end be heard.
  public static let endMargin: TimeInterval = 0.25

  /// Where playback goes, in seconds into the trimmed region of `length` seconds.
  /// Looping sounds wrap around; other sounds stay between the start and just before the end.
  public static func target(
    _ requested: TimeInterval,
    length: TimeInterval,
    loops: Bool
  ) -> TimeInterval {
    guard length > 0 else { return 0 }
    if loops {
      let wrapped = requested.truncatingRemainder(dividingBy: length)
      return wrapped < 0 ? wrapped + length : wrapped
    }
    return min(max(requested, 0), max(length - endMargin, 0))
  }
}

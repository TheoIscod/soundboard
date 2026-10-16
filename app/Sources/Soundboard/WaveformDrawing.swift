import AppKit
import SoundboardCore
import SwiftUI

/// The waveform bars alone. Equatable so SwiftUI redraws them only when what they show
/// changes, not on every selection, playhead or handle update around them.
struct WaveformBars: View, Equatable {
  let peaks: [WaveformPeak]
  /// Shown part of the sound, as fractions of its length.
  let visible: ClosedRange<Double>
  /// Part kept by the trim, as fractions of the sound's length; drawn in `color`.
  let kept: ClosedRange<Double>
  let color: Color
  let cutColor: Color

  var body: some View {
    Canvas { context, size in
      let count = max(Int(size.width), 1)
      let columns = Waveform.columns(
        of: peaks, from: visible.lowerBound, to: visible.upperBound, count: count)
      let middle = size.height / 2
      let span = visible.upperBound - visible.lowerBound
      // Two paths stroked once each: thousands of separate strokes are what made it slow.
      var keptBars = Path()
      var cutBars = Path()
      for (index, peak) in columns.enumerated() {
        let x = CGFloat(index) + 0.5
        let fraction = visible.lowerBound + span * Double(x) / Double(count)
        let top = CGPoint(x: x, y: middle - CGFloat(peak.high) * middle)
        let bottom = CGPoint(x: x, y: middle - CGFloat(peak.low) * middle + 0.5)
        if kept.contains(fraction) {
          keptBars.move(to: top)
          keptBars.addLine(to: bottom)
        } else {
          cutBars.move(to: top)
          cutBars.addLine(to: bottom)
        }
      }
      context.stroke(cutBars, with: .color(cutColor), lineWidth: 1)
      context.stroke(keptBars, with: .color(color), lineWidth: 1)
    }
  }
}

/// The red playhead, redrawn on its own at display rate while `isPlaying`, so playback
/// never redraws the waveform underneath.
struct Playhead: View {
  let isPlaying: Bool
  let position: () -> TimeInterval?
  let x: (TimeInterval, CGFloat) -> CGFloat

  var body: some View {
    TimelineView(.animation(paused: !isPlaying)) { _ in
      Canvas { context, size in
        guard let time = position() else { return }
        let playheadX = x(time, size.width)
        context.stroke(
          Path {
            $0.addLines([CGPoint(x: playheadX, y: 0), CGPoint(x: playheadX, y: size.height)])
          },
          with: .color(.red),
          lineWidth: 1.5
        )
      }
    }
    .allowsHitTesting(false)
  }
}

/// Trackpad pinch and scroll wheel over a waveform: pinching or ⌘-scrolling zooms around the
/// pointer, scrolling pans. SwiftUI has no scroll-wheel gesture on macOS, hence a local event
/// monitor, which lets events through unless the pointer is over the view.
@MainActor
final class WaveformScrollMonitor {
  /// Pointer position over the view and the view's width; nil when the pointer is elsewhere.
  var pointer: (x: CGFloat, width: CGFloat)?
  private var monitor: Any?

  func start(
    zoom: @escaping (_ factor: Double, _ fraction: Double) -> Void,
    pan: @escaping (_ widths: Double) -> Void
  ) {
    stop()
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) {
      [weak self] event in
      guard let pointer = self?.pointer, pointer.width > 0 else { return event }
      let fraction = Double(pointer.x / pointer.width)
      if event.type == .magnify {
        zoom(1 + Double(event.magnification), fraction)
        return nil
      }
      // A mouse wheel reports lines, a trackpad points.
      let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
      let deltaX = Double(event.scrollingDeltaX) * scale
      let deltaY = Double(event.scrollingDeltaY) * scale
      if event.modifierFlags.contains(.command) {
        zoom(exp(deltaY * 0.01), fraction)
      } else {
        pan(-(abs(deltaX) >= abs(deltaY) ? deltaX : deltaY) / Double(pointer.width))
      }
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}

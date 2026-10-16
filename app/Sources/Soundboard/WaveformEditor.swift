import AppKit
import SoundboardCore
import SwiftUI

/// The tile's whole sound with its trim and fades, edited by dragging four handles:
/// start and end bars, and the fade-in end and fade-out start dots along the top.
struct WaveformEditor: View {
  let tile: Tile
  let duration: TimeInterval
  let model: BoardModel

  private static let space = "waveform"
  private static let handleWidth: CGFloat = 12

  private var editor: TrimEditor { TrimEditor(duration: duration) }
  private var start: TimeInterval { tile.player.trimStart }
  private var end: TimeInterval { editor.end(of: tile.player) }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.state(of: tile) != .playing)) {
      _ in
      GeometryReader { geometry in
        let width = geometry.size.width
        ZStack(alignment: .topLeading) {
          Canvas { context, size in draw(in: &context, size: size) }
          trimHandle(at: x(start, width), size: geometry.size) {
            editor.settingStart($0, in: tile.player)
          }
          trimHandle(at: x(end, width), size: geometry.size) {
            editor.settingEnd($0, in: tile.player)
          }
          fadeHandle(at: x(start + tile.player.fadeInTime, width), width: width) {
            editor.settingFadeInEnd($0, in: tile.player)
          }
          fadeHandle(at: x(end - tile.player.fadeOutTime, width), width: width) {
            editor.settingFadeOutStart($0, in: tile.player)
          }
        }
        .coordinateSpace(.named(Self.space))
      }
    }
    .frame(height: 96)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task(id: tile.fileID) { await model.loadWaveform(for: tile) }
    .accessibilityElement()
    .accessibilityLabel("Waveform with trim and fades")
  }

  // MARK: Drawing

  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let middle = size.height / 2
    if let peaks = model.waveforms[tile.fileID], !peaks.isEmpty {
      let barWidth = size.width / CGFloat(peaks.count)
      for (index, peak) in peaks.enumerated() {
        let barX = (CGFloat(index) + 0.5) * barWidth
        let time = Double(barX / size.width) * duration
        var bar = Path()
        bar.move(to: CGPoint(x: barX, y: middle - CGFloat(peak.high) * middle))
        bar.addLine(to: CGPoint(x: barX, y: middle - CGFloat(peak.low) * middle))
        let isKept = time >= start && time <= end
        context.stroke(
          bar,
          with: .color(isKept ? Color.accentColor : .secondary),
          lineWidth: max(barWidth, 1)
        )
      }
    } else {
      context.draw(
        Text("Loading…").foregroundStyle(.secondary), at: CGPoint(x: size.width / 2, y: middle))
    }

    // Dim what the trim cuts away.
    let dim = GraphicsContext.Shading.color(.black.opacity(0.3))
    context.fill(
      Path(CGRect(x: 0, y: 0, width: x(start, size.width), height: size.height)), with: dim)
    let endX = x(end, size.width)
    context.fill(
      Path(CGRect(x: endX, y: 0, width: size.width - endX, height: size.height)), with: dim)

    // Fade envelope, linear in gain as it plays.
    var envelope = Path()
    envelope.move(to: CGPoint(x: x(start, size.width), y: size.height))
    envelope.addLine(to: CGPoint(x: x(start + tile.player.fadeInTime, size.width), y: 0))
    envelope.addLine(to: CGPoint(x: x(end - tile.player.fadeOutTime, size.width), y: 0))
    envelope.addLine(to: CGPoint(x: endX, y: size.height))
    context.stroke(envelope, with: .color(.yellow), lineWidth: 1.5)

    if let position = model.playbackPosition(of: tile), position <= end {
      let playheadX = x(position, size.width)
      context.stroke(
        Path { $0.addLines([CGPoint(x: playheadX, y: 0), CGPoint(x: playheadX, y: size.height)]) },
        with: .color(.red),
        lineWidth: 1.5
      )
    }
  }

  // MARK: Handles

  private func trimHandle(
    at handleX: CGFloat,
    size: CGSize,
    edit: @escaping (TimeInterval) -> PlayerSettings
  ) -> some View {
    Rectangle()
      .fill(Color.primary.opacity(0.9))
      .frame(width: 2, height: size.height)
      .frame(width: Self.handleWidth, height: size.height)
      .contentShape(Rectangle())
      .position(x: handleX, y: size.height / 2)
      .gesture(dragGesture(width: size.width, edit))
      .onHover { inside in
        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
      }
  }

  private func fadeHandle(
    at handleX: CGFloat,
    width: CGFloat,
    edit: @escaping (TimeInterval) -> PlayerSettings
  ) -> some View {
    Circle()
      .fill(.yellow)
      .frame(width: 10, height: 10)
      .frame(width: Self.handleWidth + 4, height: Self.handleWidth + 4)
      .contentShape(Circle())
      .position(x: handleX, y: 8)
      .gesture(dragGesture(width: width, edit))
  }

  private func dragGesture(
    width: CGFloat,
    _ edit: @escaping (TimeInterval) -> PlayerSettings
  ) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
      .onChanged { value in
        var updated = tile
        updated.player = edit(time(atX: value.location.x, width: width))
        model.update(updated)
      }
  }

  // MARK: Geometry

  private func x(_ time: TimeInterval, _ width: CGFloat) -> CGFloat {
    guard duration > 0 else { return 0 }
    return CGFloat(min(max(time / duration, 0), 1)) * width
  }

  private func time(atX x: CGFloat, width: CGFloat) -> TimeInterval {
    guard width > 0 else { return 0 }
    return Double(min(max(x / width, 0), 1)) * duration
  }
}

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

  /// Settings while a handle is dragged, saved once when it is released.
  @State private var draft: PlayerSettings?

  private var editor: TrimEditor { TrimEditor(duration: duration) }
  private var player: PlayerSettings { draft ?? tile.player }
  private var start: TimeInterval { player.trimStart }
  private var end: TimeInterval { editor.end(of: player) }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .topLeading) {
        bars
        Canvas { context, size in draw(in: &context, size: size) }
        Playhead(
          isPlaying: model.state(of: tile) == .playing,
          position: { model.playbackPosition(of: tile).flatMap { $0 <= end ? $0 : nil } },
          x: { x($0, $1) }
        )
        trimHandle(at: x(start, width), size: geometry.size) {
          editor.settingStart($0, in: player)
        }
        trimHandle(at: x(end, width), size: geometry.size) {
          editor.settingEnd($0, in: player)
        }
        fadeHandle(at: x(start + player.fadeInTime, width), width: width) {
          editor.settingFadeInEnd($0, in: player)
        }
        fadeHandle(at: x(end - player.fadeOutTime, width), width: width) {
          editor.settingFadeOutStart($0, in: player)
        }
      }
      .coordinateSpace(.named(Self.space))
    }
    .frame(height: 96)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task(id: tile.fileID) { await model.loadWaveform(for: tile) }
    .accessibilityElement()
    .accessibilityLabel("Forme d’onde avec découpe et fondus")
  }

  // MARK: Drawing

  @ViewBuilder private var bars: some View {
    if let peaks = model.waveforms[tile.fileID], !peaks.isEmpty, duration > 0 {
      WaveformBars(
        peaks: peaks,
        visible: 0...1,
        kept: start / duration...max(end / duration, start / duration),
        color: .accentColor,
        cutColor: .secondary
      )
      .equatable()
    } else {
      Text("Chargement…")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func draw(in context: inout GraphicsContext, size: CGSize) {
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
    envelope.addLine(to: CGPoint(x: x(start + player.fadeInTime, size.width), y: 0))
    envelope.addLine(to: CGPoint(x: x(end - player.fadeOutTime, size.width), y: 0))
    envelope.addLine(to: CGPoint(x: endX, y: size.height))
    context.stroke(envelope, with: .color(.yellow), lineWidth: 1.5)
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
      .onChanged { value in draft = edit(time(atX: value.location.x, width: width)) }
      .onEnded { _ in
        if let draft {
          var updated = tile
          updated.player = draft
          model.update(updated)
        }
        draft = nil
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

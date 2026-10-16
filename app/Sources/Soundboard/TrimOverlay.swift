import AppKit
import SoundboardCore
import SwiftUI

/// A tile's trim and fades drawn over its waveform and edited with four handles: start and
/// end bars, and the fade-in end and fade-out start dots along the top. Shared by the
/// inspector (whole sound) and the editor window (zoomed `viewport`).
struct TrimOverlay: View {
  /// The tile's saved settings; a drag edits a copy and hands it to `commit` on release.
  let settings: PlayerSettings
  let duration: TimeInterval
  let viewport: WaveformViewport
  /// The settings being dragged, for views drawn alongside (bar colours, readouts).
  @Binding var draft: PlayerSettings?
  let commit: (_ settings: PlayerSettings, _ actionName: String) -> Void

  /// Reset by SwiftUI when a drag is cancelled, unlike `@State`, which only `onEnded` clears.
  @GestureState private var dragged: PlayerSettings?
  private static let space = "trimOverlay"

  private var editor: TrimEditor { TrimEditor(duration: duration) }
  private var shown: PlayerSettings { dragged ?? settings }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack(alignment: .topLeading) {
        Canvas { context, size in draw(in: &context, size: size) }
          .allowsHitTesting(false)
        handle("Début", isBar: true, size: size, time: { $0.trimStart }) {
          editor.settingStart($0, in: $1)
        }
        handle("Fin", isBar: true, size: size, time: { duration - $0.trimEnd }) {
          editor.settingEnd($0, in: $1)
        }
        handle("Fondu d’entrée", isBar: false, size: size, time: { $0.trimStart + $0.fadeInTime }) {
          editor.settingFadeInEnd($0, in: $1)
        }
        handle(
          "Fondu de sortie", isBar: false, size: size,
          time: { duration - $0.trimEnd - $0.fadeOutTime }
        ) { editor.settingFadeOutStart($0, in: $1) }
      }
      .coordinateSpace(.named(Self.space))
    }
    .onChange(of: dragged) { _, dragged in draft = dragged }
  }

  private func x(_ time: TimeInterval, _ width: CGFloat) -> CGFloat {
    CGFloat(viewport.x(of: time, width: Double(width)))
  }

  /// Dims what the trim cuts away and draws the fade envelope, linear in gain as it plays.
  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let startX = x(shown.trimStart, size.width)
    let endX = x(duration - shown.trimEnd, size.width)
    let dim = GraphicsContext.Shading.color(.black.opacity(0.3))
    context.fill(Path(CGRect(x: 0, y: 0, width: max(startX, 0), height: size.height)), with: dim)
    context.fill(
      Path(CGRect(x: endX, y: 0, width: max(size.width - endX, 0), height: size.height)),
      with: dim
    )

    var envelope = Path()
    envelope.move(to: CGPoint(x: startX, y: size.height))
    envelope.addLine(to: CGPoint(x: x(shown.trimStart + shown.fadeInTime, size.width), y: 0))
    envelope.addLine(
      to: CGPoint(x: x(duration - shown.trimEnd - shown.fadeOutTime, size.width), y: 0))
    envelope.addLine(to: CGPoint(x: endX, y: size.height))
    context.stroke(envelope, with: .color(.yellow), lineWidth: 1.5)
  }

  /// A trim bar (full height) or a fade dot (along the top) at `time(settings)`.
  private func handle(
    _ name: String,
    isBar: Bool,
    size: CGSize,
    time: @escaping (PlayerSettings) -> TimeInterval,
    edit: @escaping (TimeInterval, PlayerSettings) -> PlayerSettings
  ) -> some View {
    let handleX = x(time(shown), size.width)
    // The drag moves the handle by the pointer's travel from where it was grabbed, so
    // grabbing it off its centre line doesn't make it jump; a click doesn't drag at all.
    let grabX = Double(x(time(settings), size.width))
    let dragged = { (value: DragGesture.Value) in
      edit(
        viewport.time(atX: grabX + Double(value.translation.width), width: Double(size.width)),
        settings
      )
    }
    return Group {
      if isBar {
        Rectangle()
          .fill(Color.primary.opacity(0.9))
          .frame(width: 2, height: size.height)
          .frame(width: 12, height: size.height)
          .contentShape(Rectangle())
          .hoverCursor(.resizeLeftRight)
          .position(x: handleX, y: size.height / 2)
      } else {
        Circle()
          .fill(.yellow)
          .frame(width: 11, height: 11)
          .frame(width: 18, height: 18)
          .contentShape(Circle())
          .position(x: handleX, y: 9)
      }
    }
    .opacity(handleX >= -6 && handleX <= size.width + 6 ? 1 : 0)
    .gesture(
      DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
        .updating($dragged) { value, state, _ in state = dragged(value) }
        .onEnded { value in commit(dragged(value), name) }
    )
    .help(name)
  }
}

extension View {
  /// Shows `cursor` while the pointer is over the view.
  func hoverCursor(_ cursor: NSCursor) -> some View {
    modifier(HoverCursor(cursor: cursor))
  }
}

/// Pushes the cursor on hover and pops it on exit, or when the view goes away under the
/// pointer: no hover exit arrives then, which used to leave the cursor stuck.
private struct HoverCursor: ViewModifier {
  let cursor: NSCursor
  @State private var isPushed = false

  func body(content: Content) -> some View {
    content
      .onHover { inside in
        if inside, !isPushed {
          cursor.push()
          isPushed = true
        } else if !inside, isPushed {
          NSCursor.pop()
          isPushed = false
        }
      }
      .onDisappear {
        if isPushed {
          NSCursor.pop()
          isPushed = false
        }
      }
  }
}

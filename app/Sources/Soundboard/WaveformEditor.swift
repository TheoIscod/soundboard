import SoundboardCore
import SwiftUI

/// The tile's whole sound with its trim and fades, edited by dragging four handles:
/// start and end bars, and the fade-in end and fade-out start dots along the top.
struct WaveformEditor: View {
  let tile: Tile
  let duration: TimeInterval
  let model: BoardModel

  /// Settings while a handle is dragged, saved once when it is released.
  @State private var draft: PlayerSettings?

  private var editor: TrimEditor { TrimEditor(duration: duration) }
  private var player: PlayerSettings { draft ?? tile.player }
  private var viewport: WaveformViewport { WaveformViewport(duration: duration) }

  var body: some View {
    ZStack {
      bars
      TrimOverlay(settings: tile.player, duration: duration, viewport: viewport, draft: $draft) {
        settings, _ in
        var updated = tile
        updated.player = settings
        model.update(updated)
      }
      Playhead(
        isPlaying: model.state(of: tile) == .playing,
        position: {
          model.playbackPosition(of: tile).flatMap { $0 <= editor.end(of: player) ? $0 : nil }
        },
        x: { CGFloat(viewport.x(of: $0, width: Double($1))) }
      )
    }
    .frame(height: 96)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .task(id: tile.fileID) { await model.loadWaveform(for: tile) }
    .accessibilityElement()
    .accessibilityLabel("Forme d’onde avec découpe et fondus")
  }

  @ViewBuilder private var bars: some View {
    if let peaks = model.waveforms[tile.fileID], !peaks.isEmpty, duration > 0 {
      let start = player.trimStart / duration
      WaveformBars(
        peaks: peaks,
        visible: 0...1,
        kept: start...max(editor.end(of: player) / duration, start),
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
}

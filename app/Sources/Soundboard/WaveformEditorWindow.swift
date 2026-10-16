import AppKit
import SoundboardCore
import SwiftUI

/// Identifies the editor window scene; its value is the edited tile's id.
enum EditorWindow {
  static let id = "waveform-editor"
}

/// Opens the selected tile's editor from the menu bar (⇧⌘E, Farrago's "Edit…").
struct EditorCommands: Commands {
  let model: BoardModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Tuile") {
      Button("Ouvrir l’éditeur de forme d’onde") {
        if let tile = model.selectedTile { openWindow(id: EditorWindow.id, value: tile.id) }
      }
      .keyboardShortcut("e", modifiers: [.command, .shift])
      .disabled(model.selectedTile == nil)
    }
  }
}

/// Editor window for one tile: zoomable waveform, selection, trim and fade handles,
/// crop / fade / revert on the selection, preview, and undo. Edits never change the sound file.
struct WaveformEditorWindow: View {
  let tileID: UUID
  let model: BoardModel

  var body: some View {
    if let tile = model.tile(withID: tileID), let duration = model.duration(of: tile) {
      EditorContent(tile: tile, duration: duration, model: model)
        .navigationTitle("Éditeur — \(tile.title)")
    } else {
      ContentUnavailableView("Cette tuile n’existe plus", systemImage: "waveform.slash")
    }
  }
}

private struct EditorContent: View {
  let tile: Tile
  let duration: TimeInterval
  let model: BoardModel

  @Environment(\.undoManager) private var undoManager
  @State private var viewport: WaveformViewport
  @State private var selection: TimeRange?
  /// Settings while a handle is dragged, committed once when it is released: updating the
  /// library on every mouse move redrew the whole app.
  @State private var draft: PlayerSettings?

  init(tile: Tile, duration: TimeInterval, model: BoardModel) {
    self.tile = tile
    self.duration = duration
    self.model = model
    _viewport = State(initialValue: WaveformViewport(duration: duration))
  }

  private var editor: TrimEditor { TrimEditor(duration: duration) }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      controls
      EditorWaveform(
        tile: tile,
        duration: duration,
        model: model,
        viewport: $viewport,
        selection: $selection,
        draft: $draft
      )
      .frame(minHeight: 200)
      OverviewStrip(tile: tile, duration: duration, model: model, viewport: $viewport)
        .frame(height: 36)
      readouts
    }
    .padding(14)
    .frame(minWidth: 720, minHeight: 380)
    .task(id: tile.fileID) { await model.loadEditorWaveform(for: tile) }
    .onDisappear { model.stopPreview() }
  }

  private var controls: some View {
    HStack(spacing: 6) {
      Button("Zoom arrière", systemImage: "minus.magnifyingglass") { viewport.zoomOut() }
        .keyboardShortcut("-", modifiers: .command)
      Button("Zoom avant", systemImage: "plus.magnifyingglass") { viewport.zoomIn() }
        .keyboardShortcut("+", modifiers: .command)
      Button("Ajuster", systemImage: "arrow.left.and.right") { viewport.zoomToFit() }
        .keyboardShortcut("-", modifiers: [.command, .option])
      Button("Zoom sur la sélection", systemImage: "rectangle.dashed") {
        if let selection { viewport.zoom(to: selection) }
      }
      .keyboardShortcut("=", modifiers: [.command, .option])
      .disabled(selection == nil)

      Divider().frame(height: 18)

      Button(
        model.isPreviewing ? "Arrêter" : "Écouter",
        systemImage: model.isPreviewing ? "stop.fill" : "play.fill"
      ) {
        if model.isPreviewing {
          model.stopPreview()
        } else {
          model.preview(tile, range: selection ?? TimeRange(start, end))
        }
      }
      .keyboardShortcut(.return, modifiers: .command)
      .help("Écoute la sélection, ou le son découpé sans sélection (⌘↩)")
      Button("Reculer", systemImage: "gobackward.5") { model.scan(tile, by: -Seek.scanStep) }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .help("Recule de 5 s dans l’écoute ou la lecture en cours (←, ⇧← pour 1 s)")
      Button("Avancer", systemImage: "goforward.5") { model.scan(tile, by: Seek.scanStep) }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .help("Avance de 5 s dans l’écoute ou la lecture en cours (→, ⇧→ pour 1 s)")
      // Fine steps: keyboard only.
      Button("Reculer d’une seconde") { model.scan(tile, by: -Seek.fineScanStep) }
        .keyboardShortcut(.leftArrow, modifiers: .shift)
        .frame(width: 0, height: 0)
        .hidden()
      Button("Avancer d’une seconde") { model.scan(tile, by: Seek.fineScanStep) }
        .keyboardShortcut(.rightArrow, modifiers: .shift)
        .frame(width: 0, height: 0)
        .hidden()

      Divider().frame(height: 18)

      Button("Recadrer", systemImage: "crop") {
        if let selection { apply(editor.cropping(to: selection, in: tile.player), "Recadrer") }
      }
      .keyboardShortcut("x", modifiers: [.command, .shift])
      .disabled(selection == nil)
      Button("Fondu d’entrée", systemImage: "arrow.up.right") {
        if let selection {
          apply(editor.fadingIn(over: selection, in: tile.player), "Fondu d’entrée")
        }
      }
      .keyboardShortcut("i", modifiers: [.command, .shift])
      .disabled(selection == nil)
      Button("Fondu de sortie", systemImage: "arrow.down.right") {
        if let selection {
          apply(editor.fadingOut(over: selection, in: tile.player), "Fondu de sortie")
        }
      }
      .keyboardShortcut("o", modifiers: [.command, .shift])
      .disabled(selection == nil)

      Spacer()
      Button("Revenir à l’original") {
        apply(editor.reverting(tile.player), "Revenir à l’original")
      }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.bordered)
  }

  private var readouts: some View {
    HStack(spacing: 18) {
      readout("Début", start)
      readout("Fin", end)
      readout("Fondu d’entrée", player.fadeInTime)
      readout("Fondu de sortie", player.fadeOutTime)
      if let selection {
        readout("Sélection", selection.length)
      }
      Spacer()
      Text(
        "Glissez pour sélectionner, ⌥-clic pour déplacer la lecture, pincez ou ⌘-défilez pour "
          + "zoomer ; les barres découpent, les points jaunes règlent les fondus."
      )
      .foregroundStyle(.secondary)
    }
    .font(.caption)
  }

  private func readout(_ label: String, _ seconds: TimeInterval) -> some View {
    Text("\(label) : ")
      + Text(seconds.formatted(.number.precision(.fractionLength(2))) + " s").monospacedDigit()
  }

  private var player: PlayerSettings { draft ?? tile.player }
  private var start: TimeInterval { player.trimStart }
  private var end: TimeInterval { duration - player.trimEnd }

  /// One undoable edit: the window's ⌘Z restores the previous settings.
  private func apply(_ settings: PlayerSettings, _ actionName: String) {
    EditorUndo.set(
      settings,
      previous: tile.player,
      tileID: tile.id,
      model: model,
      undoManager: undoManager,
      actionName: actionName
    )
  }
}

@MainActor
enum EditorUndo {
  /// Applies `settings` and registers the way back, which itself registers the redo.
  static func set(
    _ settings: PlayerSettings,
    previous: PlayerSettings,
    tileID: UUID,
    model: BoardModel,
    undoManager: UndoManager?,
    actionName: String
  ) {
    guard settings != previous, var tile = model.tile(withID: tileID) else { return }
    tile.player = settings
    model.update(tile)
    // The manager stores this closure, so it must not hold the manager strongly.
    undoManager?.registerUndo(withTarget: model) { [weak undoManager] model in
      MainActor.assumeIsolated {
        set(
          previous,
          previous: settings,
          tileID: tileID,
          model: model,
          undoManager: undoManager,
          actionName: actionName
        )
      }
    }
    undoManager?.setActionName(actionName)
  }
}

/// The zoomed waveform with selection, trim bars, fade dots and playhead.
private struct EditorWaveform: View {
  let tile: Tile
  let duration: TimeInterval
  let model: BoardModel
  @Binding var viewport: WaveformViewport
  @Binding var selection: TimeRange?
  @Binding var draft: PlayerSettings?

  @Environment(\.undoManager) private var undoManager
  @State private var selectionAnchor: TimeInterval?
  @State private var scrolling = WaveformScrollMonitor()

  private var player: PlayerSettings { draft ?? tile.player }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack(alignment: .topLeading) {
        bars
        Canvas { context, size in drawSelection(in: &context, size: size) }
          .contentShape(Rectangle())
          .gesture(selectionGesture(width: size.width))
        Playhead(
          isPlaying: model.isPreviewing || model.state(of: tile) == .playing,
          position: { model.previewPosition ?? model.playbackPosition(of: tile) },
          x: { CGFloat(viewport.x(of: $0, width: Double($1))) }
        )
        TrimOverlay(
          settings: tile.player,
          duration: duration,
          viewport: viewport,
          draft: $draft
        ) { settings, actionName in
          // The whole drag is one undo step, back to where it started.
          EditorUndo.set(
            settings,
            previous: tile.player,
            tileID: tile.id,
            model: model,
            undoManager: undoManager,
            actionName: actionName
          )
        }
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          scrolling.pointer = (location.x, size.width, WaveformScrollMonitor.windowUnderPointer())
        case .ended: scrolling.pointer = nil
        }
      }
    }
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .onAppear {
      scrolling.start(
        zoom: { viewport.zoom(by: $0, keepingFraction: $1) },
        pan: { viewport.scroll(by: $0 * viewport.visible.length) }
      )
    }
    .onDisappear { scrolling.stop() }
  }

  @ViewBuilder private var bars: some View {
    if let peaks = model.editorWaveforms[tile.fileID], duration > 0 {
      let visible = viewport.visible
      let keptStart = player.trimStart / duration
      WaveformBars(
        peaks: peaks,
        visible: visible.start / duration...visible.end / duration,
        kept: keptStart...max(1 - player.trimEnd / duration, keptStart),
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

  private func drawSelection(in context: inout GraphicsContext, size: CGSize) {
    guard let selection else { return }
    let from = CGFloat(viewport.x(of: selection.start, width: Double(size.width)))
    let to = CGFloat(viewport.x(of: selection.end, width: Double(size.width)))
    context.fill(
      Path(CGRect(x: from, y: 0, width: max(to - from, 1), height: size.height)),
      with: .color(Color.accentColor.opacity(0.2))
    )
  }

  /// Drag to select; a click without dragging clears the selection; ⌥-click jumps the
  /// preview or the playing tile there.
  private func selectionGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if selectionAnchor == nil, NSEvent.modifierFlags.contains(.option) {
          model.jump(tile, to: viewport.time(atX: Double(value.location.x), width: Double(width)))
          return
        }
        let anchor =
          selectionAnchor ?? viewport.time(atX: Double(value.startLocation.x), width: Double(width))
        selectionAnchor = anchor
        let current = viewport.time(atX: Double(value.location.x), width: Double(width))
        let range = TimeRange(anchor, current)
        selection = range.length > 0 ? range : nil
      }
      .onEnded { _ in selectionAnchor = nil }
  }
}

/// The whole sound with the visible span outlined; drag or click to move the view.
private struct OverviewStrip: View {
  let tile: Tile
  let duration: TimeInterval
  let model: BoardModel
  @Binding var viewport: WaveformViewport

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      if let peaks = model.editorWaveforms[tile.fileID] {
        WaveformBars(
          peaks: peaks, visible: 0...1, kept: 0...1, color: .secondary, cutColor: .secondary
        )
        .equatable()
      }
      Canvas { context, size in
        let visible = viewport.visible
        let rect = CGRect(
          x: visible.start / duration * size.width,
          y: 0.5,
          width: max(visible.length / duration * size.width, 2),
          height: size.height - 1
        )
        context.stroke(
          Path(roundedRect: rect, cornerRadius: 3), with: .color(.accentColor), lineWidth: 1.5)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { value in
          let centre = min(max(value.location.x / width, 0), 1) * duration
          let current = (viewport.visible.start + viewport.visible.end) / 2
          viewport.scroll(by: centre - current)
        }
      )
    }
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    .help("Vue d’ensemble : cliquez ou glissez pour vous déplacer")
  }
}

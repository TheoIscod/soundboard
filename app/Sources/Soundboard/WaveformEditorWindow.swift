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
        viewport: viewport,
        selection: $selection
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
      readout("Fondu d’entrée", tile.player.fadeInTime)
      readout("Fondu de sortie", tile.player.fadeOutTime)
      if let selection {
        readout("Sélection", selection.length)
      }
      Spacer()
      Text(
        "Glissez sur la forme d’onde pour sélectionner ; les barres découpent, les points jaunes règlent les fondus."
      )
      .foregroundStyle(.secondary)
    }
    .font(.caption)
  }

  private func readout(_ label: String, _ seconds: TimeInterval) -> some View {
    Text("\(label) : ")
      + Text(seconds.formatted(.number.precision(.fractionLength(2))) + " s").monospacedDigit()
  }

  private var start: TimeInterval { tile.player.trimStart }
  private var end: TimeInterval { duration - tile.player.trimEnd }

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
    // Also correct after a drag, which already applied `settings` live.
    tile.player = settings
    model.update(tile)
    undoManager?.registerUndo(withTarget: model) { model in
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
  let viewport: WaveformViewport
  @Binding var selection: TimeRange?

  @Environment(\.undoManager) private var undoManager
  private static let space = "editorWaveform"
  @State private var selectionAnchor: TimeInterval?
  /// Settings when a handle drag began, so the whole drag is one undo step.
  @State private var dragStart: PlayerSettings?

  private var editor: TrimEditor { TrimEditor(duration: duration) }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { _ in
      GeometryReader { geometry in
        let size = geometry.size
        ZStack(alignment: .topLeading) {
          Canvas { context, size in draw(in: &context, size: size) }
            .contentShape(Rectangle())
            .gesture(selectionGesture(width: size.width))
          handle(at: tile.player.trimStart, size: size, isBar: true, name: "Début") {
            editor.settingStart($0, in: $1)
          }
          handle(at: duration - tile.player.trimEnd, size: size, isBar: true, name: "Fin") {
            editor.settingEnd($0, in: $1)
          }
          handle(
            at: tile.player.trimStart + tile.player.fadeInTime,
            size: size,
            isBar: false,
            name: "Fondu d’entrée"
          ) { editor.settingFadeInEnd($0, in: $1) }
          handle(
            at: duration - tile.player.trimEnd - tile.player.fadeOutTime,
            size: size,
            isBar: false,
            name: "Fondu de sortie"
          ) { editor.settingFadeOutStart($0, in: $1) }
        }
        .coordinateSpace(.named(Self.space))
      }
    }
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var isPlaying: Bool {
    model.isPreviewing || model.state(of: tile) == .playing
  }

  private func draw(in context: inout GraphicsContext, size: CGSize) {
    let middle = size.height / 2
    let width = Double(size.width)
    let visible = viewport.visible

    if let peaks = model.editorWaveforms[tile.fileID] {
      let columns = Waveform.columns(
        of: peaks,
        from: visible.start / duration,
        to: visible.end / duration,
        count: max(Int(width), 1)
      )
      for (index, peak) in columns.enumerated() {
        let x = CGFloat(index) + 0.5
        let time = viewport.time(atX: Double(x), width: width)
        var bar = Path()
        bar.move(to: CGPoint(x: x, y: middle - CGFloat(peak.high) * middle))
        bar.addLine(to: CGPoint(x: x, y: middle - CGFloat(peak.low) * middle + 0.5))
        let kept = time >= tile.player.trimStart && time <= duration - tile.player.trimEnd
        context.stroke(bar, with: .color(kept ? Color.accentColor : .secondary), lineWidth: 1)
      }
    } else {
      context.draw(
        Text("Chargement…").foregroundStyle(.secondary),
        at: CGPoint(x: size.width / 2, y: middle)
      )
    }

    let startX = CGFloat(viewport.x(of: tile.player.trimStart, width: width))
    let endX = CGFloat(viewport.x(of: duration - tile.player.trimEnd, width: width))
    let dim = GraphicsContext.Shading.color(.black.opacity(0.3))
    context.fill(Path(CGRect(x: 0, y: 0, width: max(startX, 0), height: size.height)), with: dim)
    context.fill(
      Path(CGRect(x: endX, y: 0, width: max(size.width - endX, 0), height: size.height)),
      with: dim
    )

    if let selection {
      let from = CGFloat(viewport.x(of: selection.start, width: width))
      let to = CGFloat(viewport.x(of: selection.end, width: width))
      context.fill(
        Path(CGRect(x: from, y: 0, width: max(to - from, 1), height: size.height)),
        with: .color(Color.accentColor.opacity(0.2))
      )
    }

    var envelope = Path()
    envelope.move(to: CGPoint(x: startX, y: size.height))
    envelope.addLine(
      to: CGPoint(
        x: CGFloat(viewport.x(of: tile.player.trimStart + tile.player.fadeInTime, width: width)),
        y: 0
      )
    )
    envelope.addLine(
      to: CGPoint(
        x: CGFloat(
          viewport.x(
            of: duration - tile.player.trimEnd - tile.player.fadeOutTime,
            width: width
          )
        ),
        y: 0
      )
    )
    envelope.addLine(to: CGPoint(x: endX, y: size.height))
    context.stroke(envelope, with: .color(.yellow), lineWidth: 1.5)

    if let position = model.previewPosition ?? model.playbackPosition(of: tile) {
      let x = CGFloat(viewport.x(of: position, width: width))
      context.stroke(
        Path { $0.addLines([CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)]) },
        with: .color(.red),
        lineWidth: 1.5
      )
    }
  }

  /// Drag to select; a click without dragging clears the selection.
  private func selectionGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
      .onChanged { value in
        let anchor =
          selectionAnchor ?? viewport.time(atX: Double(value.startLocation.x), width: Double(width))
        selectionAnchor = anchor
        let current = viewport.time(atX: Double(value.location.x), width: Double(width))
        let range = TimeRange(anchor, current)
        selection = range.length > 0 ? range : nil
      }
      .onEnded { _ in selectionAnchor = nil }
  }

  /// A trim bar (full height) or a fade dot (along the top) dragged to a time.
  private func handle(
    at time: TimeInterval,
    size: CGSize,
    isBar: Bool,
    name: String,
    edit: @escaping (TimeInterval, PlayerSettings) -> PlayerSettings
  ) -> some View {
    let x = CGFloat(viewport.x(of: time, width: Double(size.width)))
    return Group {
      if isBar {
        Rectangle()
          .fill(Color.primary.opacity(0.9))
          .frame(width: 2, height: size.height)
          .frame(width: 12, height: size.height)
          .contentShape(Rectangle())
          .position(x: x, y: size.height / 2)
      } else {
        Circle()
          .fill(.yellow)
          .frame(width: 11, height: 11)
          .frame(width: 18, height: 18)
          .contentShape(Circle())
          .position(x: x, y: 9)
      }
    }
    .opacity(x >= -6 && x <= size.width + 6 ? 1 : 0)
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
        .onChanged { value in
          let original = dragStart ?? tile.player
          dragStart = original
          let time = viewport.time(atX: Double(value.location.x), width: Double(size.width))
          var updated = tile
          updated.player = edit(time, tile.player)
          model.update(updated)
        }
        .onEnded { _ in
          // The whole drag is one undo step, back to where it started.
          if let original = dragStart, let final = model.tile(withID: tile.id)?.player {
            EditorUndo.set(
              final,
              previous: original,
              tileID: tile.id,
              model: model,
              undoManager: undoManager,
              actionName: name
            )
          }
          dragStart = nil
        }
    )
    .help(name)
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
      Canvas { context, size in
        let middle = size.height / 2
        if let peaks = model.editorWaveforms[tile.fileID] {
          let columns = Waveform.columns(of: peaks, from: 0, to: 1, count: max(Int(width), 1))
          for (index, peak) in columns.enumerated() {
            var bar = Path()
            let x = CGFloat(index) + 0.5
            bar.move(to: CGPoint(x: x, y: middle - CGFloat(peak.high) * middle))
            bar.addLine(to: CGPoint(x: x, y: middle - CGFloat(peak.low) * middle + 0.5))
            context.stroke(bar, with: .color(.secondary), lineWidth: 1)
          }
        }
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

import SoundboardCore
import SwiftUI

struct BoardView: View {
  @Bindable var model: BoardModel
  @State private var isDropTargeted = false
  @State private var isInspectorPresented = false
  @State private var tilePendingDeletion: Tile?
  @State private var isSetOptionsPresented = false
  /// Where each visible tile is laid out in `BoardSpace`, to find the drop target.
  @State private var tileFrames: [UUID: CGRect] = [:]

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 10),
    count: BoardModel.gridColumns
  )

  var body: some View {
    Group {
      if model.soundSet.tiles.isEmpty {
        ContentUnavailableView(
          "Drop audio files here",
          systemImage: "waveform",
          description: Text("Each file becomes a tile. Click a tile to play or stop it.")
        )
      } else if model.soundSet.displayMode == .list {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(model.soundSet.listOrder.enumerated()), id: \.element.id) {
              index, tile in
              ListRowView(
                tile: tile,
                number: index + 1,
                state: model.state(of: tile),
                isSelected: model.selectedTileID == tile.id,
                model: model,
                onEdit: { edit(tile) },
                onDelete: { tilePendingDeletion = tile },
                onDrop: { drop(tile, at: $0) }
              )
              .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(BoardSpace.name))
              } action: { frame in
                tileFrames[tile.id] = frame
              }
            }
          }
          .padding(12)
          .coordinateSpace(.named(BoardSpace.name))
        }
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.soundSet.gridOrder) { tile in
              TileView(
                tile: tile,
                state: model.state(of: tile),
                isSelected: model.selectedTileID == tile.id,
                model: model,
                onEdit: { edit(tile) },
                onDelete: { tilePendingDeletion = tile },
                onDrop: { drop(tile, at: $0) }
              )
              .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(BoardSpace.name))
              } action: { frame in
                tileFrames[tile.id] = frame
              }
            }
          }
          .padding(12)
          .coordinateSpace(.named(BoardSpace.name))
        }
      }
    }
    .frame(minWidth: 640, minHeight: 400)
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.accentColor, lineWidth: 3)
          .padding(4)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      model.addFiles(urls)
    } isTargeted: {
      isDropTargeted = $0
    }
    .navigationTitle(model.soundSet.title)
    .inspector(isPresented: $isInspectorPresented) {
      Group {
        if let tile = model.selectedTile {
          TileInspector(tile: tile, model: model) { tilePendingDeletion = tile }
        } else {
          ContentUnavailableView("No Tile Selected", systemImage: "square.dashed")
        }
      }
      .inspectorColumnWidth(min: 260, ideal: 300)
    }
    .toolbar {
      Picker(
        "Display",
        selection: Binding(
          get: { model.soundSet.displayMode },
          set: { model.setDisplayMode($0) }
        )
      ) {
        Label("Grid", systemImage: "square.grid.3x3").tag(DisplayMode.grid)
        Label("List", systemImage: "list.bullet").tag(DisplayMode.list)
      }
      .pickerStyle(.segmented)
      .help("Show the set as a grid or a list")
      Button("Set Options", systemImage: "slider.horizontal.3") { isSetOptionsPresented = true }
        .help("What happens when a sound ends in list mode")
        .popover(isPresented: $isSetOptionsPresented) { SetOptionsView(model: model) }
      MasterVolumeControl(model: model)
      Button("Fade Out All", systemImage: "speaker.wave.1") { model.fadeOutAll() }
        .keyboardShortcut("-", modifiers: [])
      Button("Stop All", systemImage: "stop.fill") { model.stopAll() }
        .keyboardShortcut(.escape, modifiers: [])
      Button("Inspector", systemImage: "sidebar.trailing") { isInspectorPresented.toggle() }
        .keyboardShortcut("i", modifiers: .command)
    }
    .confirmationDialog(
      "Delete “\(tilePendingDeletion?.title ?? "")”?",
      isPresented: Binding(
        get: { tilePendingDeletion != nil },
        set: { if !$0 { tilePendingDeletion = nil } }
      )
    ) {
      Button("Delete Tile", role: .destructive) {
        if let tile = tilePendingDeletion { model.deleteTile(tile) }
        tilePendingDeletion = nil
      }
    } message: {
      Text("The copy of its sound in this set will be removed. This can’t be undone.")
    }
    .alert(
      "Playback error",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private func edit(_ tile: Tile) {
    model.selectedTileID = tile.id
    isInspectorPresented = true
  }

  /// Drops onto the tile laid out closest to the release point; dropping nearest the
  /// dragged tile's own place leaves the order unchanged.
  private func drop(_ tile: Tile, at location: CGPoint) {
    let visible = Set(model.soundSet.tiles.map(\.id))
    let nearest =
      tileFrames
      .filter { visible.contains($0.key) }
      .min { distance(from: location, to: $0.value) < distance(from: location, to: $1.value) }
    guard let target = nearest?.key else { return }
    model.moveTile(tile.id, onto: target)
  }

  private func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
    hypot(point.x - frame.midX, point.y - frame.midY)
  }
}

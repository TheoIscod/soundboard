import SoundboardCore
import SwiftUI

struct BoardView: View {
  @Bindable var model: BoardModel
  @State private var isDropTargeted = false
  @State private var isSetOptionsPresented = false
  /// Where each visible tile is laid out in `BoardSpace`, to find the drop target.
  @State private var tileFrames: [UUID: CGRect] = [:]

  private let columns = Array(
    repeating: GridItem(.flexible(), spacing: 10),
    count: BoardModel.gridColumns
  )

  var body: some View {
    Group {
      if model.soundSet.isSmart, model.shownSet.tiles.isEmpty {
        ContentUnavailableView {
          Label("Aucune tuile ne correspond", systemImage: "gearshape")
        } description: {
          Text("Ce smart set montre les tuiles des autres sets qui suivent ses règles.")
        } actions: {
          Button("Modifier les règles…") { model.rulesEditorSetID = model.soundSet.id }
        }
      } else if model.shownSet.tiles.isEmpty {
        ContentUnavailableView(
          "Déposez des fichiers audio ici",
          systemImage: "waveform",
          description: Text(
            "Chaque fichier devient une tuile : cliquez dessus pour la lancer ou l’arrêter. "
              + "Déposez un set pour l’ouvrir."
          )
        )
      } else if model.soundSet.displayMode == .list {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(model.shownSet.listOrder.enumerated()), id: \.element.id) {
              index, tile in
              ListRowView(
                tile: tile,
                number: index + 1,
                state: model.state(of: tile),
                isSelected: model.selectedTileID == tile.id,
                model: model,
                onEdit: { edit(tile) },
                onDelete: model.soundSet.isSmart ? nil : { model.tilePendingDeletion = tile },
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
            ForEach(model.shownSet.gridOrder) { tile in
              TileView(
                tile: tile,
                state: model.state(of: tile),
                isSelected: model.selectedTileID == tile.id,
                model: model,
                onEdit: { edit(tile) },
                onDelete: model.soundSet.isSmart ? nil : { model.tilePendingDeletion = tile },
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
      model.drop(urls)
    } isTargeted: {
      isDropTargeted = $0
    }
    .navigationTitle(model.soundSet.title)
    .toolbar {
      // Centred so the controls stay above the board and don't spread over the inspector.
      ToolbarItemGroup(placement: .principal) {
        Picker(
          "Affichage",
          selection: Binding(
            get: { model.soundSet.displayMode },
            set: { model.setDisplayMode($0) }
          )
        ) {
          Label("Grille", systemImage: "square.grid.3x3").tag(DisplayMode.grid)
          Label("Liste", systemImage: "list.bullet").tag(DisplayMode.list)
        }
        .pickerStyle(.segmented)
        .help("Afficher le set en grille ou en liste")
        Button("Options du set", systemImage: "slider.horizontal.3") {
          isSetOptionsPresented = true
        }
        .help("Ce qui se passe à la fin d’un son, en mode liste")
        .popover(isPresented: $isSetOptionsPresented) { SetOptionsView(model: model) }
        MasterVolumeControl(model: model)
        Button("Fondu de sortie général", systemImage: "speaker.wave.1") { model.fadeOutAll() }
          .keyboardShortcut("-", modifiers: [])
        Button("Tout mettre en pause", systemImage: "pause.fill") { model.togglePauseAll() }
          .keyboardShortcut(.space, modifiers: [])
          .help("Met en pause tout ce qui joue, ou reprend ce qui est en pause (Espace)")
        Button("Tout arrêter", systemImage: "stop.fill") { model.stopAll() }
          .keyboardShortcut(.escape, modifiers: [])
      }
      ToolbarItem(placement: .primaryAction) {
        Button("Inspecteur", systemImage: "sidebar.trailing") {
          model.isInspectorPresented.toggle()
        }
        .keyboardShortcut("i", modifiers: .command)
      }
    }
    .confirmationDialog(
      "Supprimer « \(model.tilePendingDeletion?.title ?? "") » ?",
      isPresented: Binding(
        get: { model.tilePendingDeletion != nil },
        set: { if !$0 { model.tilePendingDeletion = nil } }
      )
    ) {
      Button("Supprimer la tuile", role: .destructive) {
        if let tile = model.tilePendingDeletion { model.deleteTile(tile) }
        model.tilePendingDeletion = nil
      }
    } message: {
      Text("La copie de son son dans ce set sera supprimée. Cette action est irréversible.")
    }
    .alert(
      "Un problème est survenu",
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
    model.isInspectorPresented = true
  }

  /// Drops onto the tile laid out closest to the release point; dropping nearest the
  /// dragged tile's own place leaves the order unchanged.
  private func drop(_ tile: Tile, at location: CGPoint) {
    let visible = Set(model.shownSet.tiles.map(\.id))
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

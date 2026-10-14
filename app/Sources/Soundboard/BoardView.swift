import SoundboardCore
import SwiftUI

struct BoardView: View {
  @Bindable var model: BoardModel
  @State private var isDropTargeted = false

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
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.orderedTiles) { tile in
              TileView(tile: tile, state: model.state(of: tile), model: model)
            }
          }
          .padding(12)
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
    .toolbar {
      Button("Fade Out All", systemImage: "speaker.wave.1") { model.fadeOutAll() }
        .keyboardShortcut("-", modifiers: [])
      Button("Stop All", systemImage: "stop.fill") { model.stopAll() }
        .keyboardShortcut(.escape, modifiers: [])
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
}

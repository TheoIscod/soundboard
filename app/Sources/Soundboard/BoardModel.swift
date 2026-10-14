import Foundation
import Observation
import SoundboardCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class BoardModel {
  static let gridColumns = 6

  var soundSet = SoundSet(title: "Untitled Set")
  var errorMessage: String?

  private var coordinator = PlaybackCoordinator()
  // Sets are not saved yet, so dropped files are played from where they are.
  private var fileURLs: [UUID: URL] = [:]
  @ObservationIgnored private let engine = AudioEngine()

  init() {
    engine.onVoiceFinished = { [weak self] tileID in
      self?.coordinator.voiceDidFinish(tileID)
    }
  }

  var orderedTiles: [Tile] {
    soundSet.tiles.sorted {
      ($0.gridPosition.row, $0.gridPosition.column) < ($1.gridPosition.row, $1.gridPosition.column)
    }
  }

  func state(of tile: Tile) -> VoiceState? {
    coordinator.state(of: tile.id)
  }

  /// Adds one tile per audio file; returns false if none of the URLs were audio.
  @discardableResult
  func addFiles(_ urls: [URL]) -> Bool {
    let audioURLs = urls.filter { url in
      (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .audio)
        ?? false
    }
    for url in audioURLs {
      let index = soundSet.tiles.count
      var tile = Tile(
        fileID: UUID(),
        originalFileName: url.lastPathComponent,
        title: url.deletingPathExtension().lastPathComponent
      )
      tile.gridPosition = GridPosition(
        column: index % Self.gridColumns,
        row: index / Self.gridColumns
      )
      tile.color = TileColor.allCases[index % TileColor.allCases.count]
      fileURLs[tile.fileID] = url
      soundSet.tiles.append(tile)
    }
    return !audioURLs.isEmpty
  }

  func press(_ tile: Tile, modifier: TriggerModifier) {
    perform(coordinator.press(tile, modifier: modifier))
  }

  func release(_ tile: Tile) {
    perform(coordinator.release(tile))
  }

  func stopAll() {
    perform(coordinator.stopAll())
  }

  func fadeOutAll() {
    perform(coordinator.fadeOutAll())
  }

  func update(_ tile: Tile) {
    guard let index = soundSet.tiles.firstIndex(where: { $0.id == tile.id }) else { return }
    soundSet.tiles[index] = tile
  }

  private func perform(_ commands: [PlaybackCommand]) {
    for command in commands {
      switch command {
      case .start(let tileID):
        start(tileID)
      case .stop(let tileID, let fade):
        engine.stop(tileID, fade: fade)
      case .pause(let tileID):
        engine.pause(tileID)
      case .resume(let tileID):
        engine.resume(tileID)
      }
    }
  }

  private func start(_ tileID: UUID) {
    guard let tile = soundSet.tiles.first(where: { $0.id == tileID }),
      let url = fileURLs[tile.fileID]
    else {
      coordinator.voiceDidFinish(tileID)
      return
    }
    do {
      try engine.start(tile, url: url)
    } catch {
      coordinator.voiceDidFinish(tileID)
      errorMessage = "Couldn’t play “\(tile.title)”: \(error.localizedDescription)"
    }
  }
}

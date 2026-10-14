import Foundation
import Observation
import SoundboardCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class BoardModel {
  static let gridColumns = 6
  private static let selectedSetKey = "selectedSetID"
  private static let masterVolumeKey = "masterVolume"

  private(set) var library: SoundLibrary
  /// Applies to every set, so it is a preference rather than part of a set.
  var master: MasterVolume {
    didSet {
      engine.setMasterGain(master.gain)
      saveMaster()
    }
  }
  /// Tile shown in the inspector.
  var selectedTileID: UUID?
  var errorMessage: String?

  private var coordinator = PlaybackCoordinator()
  @ObservationIgnored private let store: SetStore?
  @ObservationIgnored private let engine = AudioEngine()
  @ObservationIgnored private var durations: [UUID: TimeInterval] = [:]

  init() {
    var store: SetStore?
    var loaded: [SoundSet] = []
    var loadError: String?
    do {
      let library = SetStore(directory: try SetStore.defaultDirectory())
      store = library
      loaded = try library.loadAll()
    } catch {
      loadError = "Couldn’t open the sound library: \(error.localizedDescription)"
    }
    self.store = store
    let remembered = UserDefaults.standard.string(forKey: Self.selectedSetKey).flatMap(UUID.init)
    library = SoundLibrary(sets: loaded, selectedSetID: remembered)
    master = Self.loadMaster()
    errorMessage = loadError
    engine.setMasterGain(master.gain)

    engine.onVoiceFinished = { [weak self] tileID in
      self?.coordinator.voiceDidFinish(tileID)
    }
  }

  var soundSet: SoundSet { library.selectedSet }

  var orderedTiles: [Tile] {
    soundSet.tiles.sorted {
      ($0.gridPosition.row, $0.gridPosition.column) < ($1.gridPosition.row, $1.gridPosition.column)
    }
  }

  func state(of tile: Tile) -> VoiceState? {
    coordinator.state(of: tile.id)
  }

  // MARK: Sets

  func selectSet(_ id: UUID) {
    library.select(id)
    rememberSelection()
  }

  func selectNextSet() {
    library.selectNextSet()
    rememberSelection()
  }

  func selectPreviousSet() {
    library.selectPreviousSet()
    rememberSelection()
  }

  func addSet() {
    let set = library.addSet()
    rememberSelection()
    save(set)
  }

  func renameSet(_ id: UUID, to title: String) {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, var set = library.set(withID: id), set.title != title else { return }
    set.title = title
    library.replace(set)
    save(set)
  }

  func canDeleteSet() -> Bool {
    library.sets.count > 1
  }

  func deleteSet(_ id: UUID) {
    guard let set = library.set(withID: id) else { return }
    // Sounds of a deleted set must not keep playing from files that are gone.
    for tile in set.tiles where coordinator.state(of: tile.id) != nil {
      engine.stop(tile.id, fade: nil)
      coordinator.voiceDidFinish(tile.id)
    }
    guard library.removeSet(id) else { return }
    rememberSelection()
    do {
      try store?.delete(id)
    } catch {
      errorMessage = "Couldn’t delete “\(set.title)”: \(error.localizedDescription)"
    }
  }

  // MARK: Tiles

  /// Adds one tile per audio file to the shown set, copying the file into it;
  /// returns false if none were audio.
  @discardableResult
  func addFiles(_ urls: [URL]) -> Bool {
    guard let store else {
      errorMessage = "Sounds can’t be added because the sound library couldn’t be opened."
      return false
    }
    let audioURLs = urls.filter { url in
      (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .audio)
        ?? false
    }
    var set = soundSet
    for url in audioURLs {
      var tile = Tile(
        fileID: UUID(),
        originalFileName: url.lastPathComponent,
        title: url.deletingPathExtension().lastPathComponent
      )
      tile.gridPosition = set.nextFreeGridPosition(columns: Self.gridColumns)
      tile.color = TileColor.allCases[set.tiles.count % TileColor.allCases.count]
      do {
        try store.importSound(from: url, for: tile, in: set.id)
      } catch {
        errorMessage = "Couldn’t add “\(tile.title)”: \(error.localizedDescription)"
        continue
      }
      set.tiles.append(tile)
    }
    library.replace(set)
    save(set)
    return !audioURLs.isEmpty
  }

  func update(_ tile: Tile) {
    guard var set = library.set(containingTile: tile.id),
      let index = set.tiles.firstIndex(where: { $0.id == tile.id })
    else { return }
    set.tiles[index] = tile
    library.replace(set)
    engine.update(tile)
    save(set)
  }

  var selectedTile: Tile? {
    guard let selectedTileID else { return nil }
    return library.set(containingTile: selectedTileID)?.tiles.first { $0.id == selectedTileID }
  }

  /// Removes the tile and its copied sound, stopping it first if it plays.
  func deleteTile(_ tile: Tile) {
    guard var set = library.set(containingTile: tile.id) else { return }
    if coordinator.state(of: tile.id) != nil {
      engine.stop(tile.id, fade: nil)
      coordinator.voiceDidFinish(tile.id)
    }
    set.tiles.removeAll { $0.id == tile.id }
    library.replace(set)
    if selectedTileID == tile.id { selectedTileID = nil }
    save(set)
    do {
      try store?.removeSound(for: tile, in: set.id)
    } catch {
      errorMessage = "Couldn’t remove the sound of “\(tile.title)”: \(error.localizedDescription)"
    }
  }

  /// Length of the tile's whole sound file, or nil if it can't be read.
  func duration(of tile: Tile) -> TimeInterval? {
    if let cached = durations[tile.fileID] { return cached }
    guard let set = library.set(containingTile: tile.id),
      let url = store?.soundURL(for: tile, in: set.id),
      let duration = try? engine.duration(of: url)
    else { return nil }
    durations[tile.fileID] = duration
    return duration
  }

  // MARK: Playback

  func press(_ tile: Tile, modifier: TriggerModifier) {
    selectedTileID = tile.id
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
    guard let set = library.set(containingTile: tileID),
      let tile = set.tiles.first(where: { $0.id == tileID }),
      let url = store?.soundURL(for: tile, in: set.id)
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

  // MARK: Persistence

  private func save(_ set: SoundSet) {
    do {
      try store?.save(set)
    } catch {
      errorMessage = "Couldn’t save “\(set.title)”: \(error.localizedDescription)"
    }
  }

  private func saveMaster() {
    do {
      UserDefaults.standard.set(try JSONEncoder().encode(master), forKey: Self.masterVolumeKey)
    } catch {
      errorMessage = "Couldn’t save the master volume: \(error.localizedDescription)"
    }
  }

  /// A missing or unreadable preference falls back to the defaults (A 100 %, B 40 %).
  private static func loadMaster() -> MasterVolume {
    guard let data = UserDefaults.standard.data(forKey: masterVolumeKey),
      let master = try? JSONDecoder().decode(MasterVolume.self, from: data)
    else { return MasterVolume() }
    return master
  }

  private func rememberSelection() {
    UserDefaults.standard.set(library.selectedSetID.uuidString, forKey: Self.selectedSetKey)
  }
}

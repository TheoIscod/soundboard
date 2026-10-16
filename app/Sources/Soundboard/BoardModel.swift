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
  /// Waveform peaks by sound file, loaded on demand by the editor.
  private(set) var waveforms: [UUID: [WaveformPeak]] = [:]

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
      self?.cueNext(after: tileID)
    }
    engine.onAdvancePoint = { [weak self] tileID, lead in
      self?.advance(from: tileID, lead: lead)
    }
  }

  var soundSet: SoundSet { library.selectedSet }

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

  /// Copies the shown set (plist and sounds) to a `.soundset` package at `destination`.
  func exportShownSet(to destination: URL) {
    do {
      guard let store else { throw BoardModelError.libraryUnavailable }
      try store.export(soundSet, to: destination)
    } catch {
      errorMessage = "Couldn’t export “\(soundSet.title)”: \(error.localizedDescription)"
    }
  }

  /// Adds `.soundset` packages and Farrago `.farragoset` sets to the library and shows the
  /// last one imported. Problems are reported once all packages have been tried.
  func importSets(from urls: [URL]) {
    var problems: [String] = []
    for url in urls {
      let name = url.lastPathComponent
      do {
        guard let store else { throw BoardModelError.libraryUnavailable }
        let set: SoundSet
        switch url.pathExtension.lowercased() {
        case SetStore.packageExtension:
          set = try store.importPackage(at: url)
        case "farragoset":
          let imported = try FarragoImport.read(package: url, packetDuration: SetFiles.seconds)
          set = try store.add(imported)
          if !imported.skippedTileTitles.isEmpty {
            problems.append(
              "\(name): sounds missing for \(imported.skippedTileTitles.joined(separator: ", "))"
            )
          }
        default:
          problems.append("\(name): not a .soundset or .farragoset")
          continue
        }
        library.add(set)
        rememberSelection()
      } catch {
        problems.append("\(name): \(error.localizedDescription)")
      }
    }
    if !problems.isEmpty {
      errorMessage = "Some sets couldn’t be fully imported.\n" + problems.joined(separator: "\n")
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
      tile.listIndex = set.nextListIndex
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

  /// Loads the tile's waveform once, off the main actor.
  func loadWaveform(for tile: Tile) async {
    guard waveforms[tile.fileID] == nil,
      let set = library.set(containingTile: tile.id),
      let url = store?.soundURL(for: tile, in: set.id)
    else { return }
    do {
      let peaks = try await Task.detached(priority: .userInitiated) {
        try WaveformLoader.peaks(of: url)
      }.value
      waveforms[tile.fileID] = peaks
    } catch {
      errorMessage = "Couldn’t draw the waveform of “\(tile.title)”: \(error.localizedDescription)"
    }
  }

  /// Where playback is, in seconds into the whole file, while the tile sounds.
  func playbackPosition(of tile: Tile) -> TimeInterval? {
    engine.position(of: tile.id).map { tile.player.trimStart + $0 }
  }

  // MARK: Playback

  func press(_ tile: Tile, modifier: TriggerModifier) {
    selectedTileID = tile.id
    perform(coordinator.press(tile, modifier: modifier, listMode: isInListMode(tile)))
  }

  func release(_ tile: Tile) {
    perform(coordinator.release(tile, listMode: isInListMode(tile)))
  }

  /// Plays (or stops) the selected tile of the shown set, e.g. the one Cue next moved to.
  func playSelection() {
    guard let tile = selectedTile, soundSet.tiles.contains(where: { $0.id == tile.id }) else {
      return
    }
    press(tile, modifier: .none)
  }

  func stopAll() {
    perform(coordinator.stopAll())
  }

  func togglePauseAll() {
    perform(coordinator.togglePauseAll())
  }

  /// Plays the shown set's tile for `key`; returns false when no tile uses that key.
  func handleHotkey(_ key: String, isKeyDown: Bool, shift: Bool) -> Bool {
    guard let tile = soundSet.tile(forHotkey: key) else { return false }
    if isKeyDown {
      press(tile, modifier: shift ? .pause : .none)
    } else {
      release(tile)
    }
    return true
  }

  /// Gives the tile a hotkey (taking it from another tile of its set); nil clears it.
  func setHotkey(_ key: String?, for tile: Tile) {
    guard var set = library.set(containingTile: tile.id) else { return }
    set.assignHotkey(key, to: tile.id)
    library.replace(set)
    save(set)
  }

  func fadeOutAll() {
    perform(coordinator.fadeOutAll())
  }

  private func perform(_ commands: [PlaybackCommand]) {
    for command in commands {
      switch command {
      case .start(let tileID, let fadeIn):
        start(tileID, fadeIn: fadeIn)
      case .stop(let tileID, let fade):
        engine.stop(tileID, fade: fade)
        cueNext(after: tileID)
      case .pause(let tileID):
        engine.pause(tileID)
      case .resume(let tileID):
        engine.resume(tileID)
      }
    }
  }

  private func start(_ tileID: UUID, fadeIn: TimeInterval) {
    guard let set = library.set(containingTile: tileID),
      let tile = set.tiles.first(where: { $0.id == tileID }),
      let url = store?.soundURL(for: tile, in: set.id)
    else {
      coordinator.voiceDidFinish(tileID)
      return
    }
    do {
      try engine.start(
        tile,
        url: url,
        fadeIn: fadeIn,
        continuousCrossfade: set.continuousCrossfade
      )
    } catch {
      coordinator.voiceDidFinish(tileID)
      errorMessage = "Couldn’t play “\(tile.title)”: \(error.localizedDescription)"
      return
    }
    var played = tile
    played.lastPlayed = Date()
    update(played)
  }

  /// Hold to Play tiles start on mouse-down; every other tile on mouse-up.
  func startsOnPress(_ tile: Tile) -> Bool {
    tile.isEnabled && tile.holdToPlay && !isInListMode(tile)
  }

  /// Moves a tile of the shown set to the place of `targetID` in the current display order.
  func moveTile(_ tileID: UUID, onto targetID: UUID) {
    guard tileID != targetID,
      let index = soundSet.displayOrder.firstIndex(where: { $0.id == targetID })
    else { return }
    updateShownSet { $0.moveTile(tileID, to: index, gridColumns: Self.gridColumns) }
    selectedTileID = tileID
  }

  private func isInListMode(_ tile: Tile) -> Bool {
    library.set(containingTile: tile.id)?.displayMode == .list
  }

  /// Continuous: the tile reached its crossfade point, start the next one.
  private func advance(from tileID: UUID, lead: TimeInterval) {
    guard let set = library.set(containingTile: tileID),
      let outgoing = set.tiles.first(where: { $0.id == tileID }),
      let next = set.nextPlayableTile(after: tileID)
    else { return }
    let commands = coordinator.crossfade(from: outgoing, to: next, duration: lead)
    guard !commands.isEmpty else { return }
    selectedTileID = next.id
    perform(commands)
  }

  /// Cue next: when a tile stops, select the following one without playing it.
  private func cueNext(after tileID: UUID) {
    guard let next = library.set(containingTile: tileID)?.tileToCue(afterStopping: tileID) else {
      return
    }
    selectedTileID = next.id
  }

  // MARK: Set options

  func setDisplayMode(_ mode: DisplayMode) {
    updateShownSet { $0.displayMode = mode }
  }

  func setPlaybackMode(_ mode: PlaybackMode) {
    updateShownSet { $0.playbackMode = mode }
  }

  func setCrossfadeDuration(_ duration: TimeInterval) {
    updateShownSet { $0.crossfadeDuration = max(duration, 0) }
  }

  /// Clears the played marks of the shown set and selects its first playable tile.
  func resetList() {
    updateShownSet { set in
      for index in set.tiles.indices { set.tiles[index].lastPlayed = nil }
    }
    selectedTileID = soundSet.firstPlayableTile?.id
  }

  private func updateShownSet(_ change: (inout SoundSet) -> Void) {
    var set = soundSet
    change(&set)
    library.replace(set)
    save(set)
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

enum BoardModelError: LocalizedError {
  case libraryUnavailable

  var errorDescription: String? {
    switch self {
    case .libraryUnavailable: "The sound library couldn’t be opened."
    }
  }
}

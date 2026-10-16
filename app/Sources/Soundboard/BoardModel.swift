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
  var isInspectorPresented = false
  /// Tile waiting for the user to confirm its deletion.
  var tilePendingDeletion: Tile?
  var errorMessage: String?

  private var coordinator = PlaybackCoordinator()
  @ObservationIgnored private let store: SetStore?
  @ObservationIgnored private let engine = AudioEngine()
  /// OSC remote control and feedback; its settings are edited in the Settings window.
  let osc = OSCService()
  /// Lights controller pads while their tiles play; its destination is chosen in Settings.
  let midiOutput = MIDIOutput()
  @ObservationIgnored private var durations: [UUID: TimeInterval] = [:]
  /// Waveform peaks by sound file, loaded on demand by the editor.
  private(set) var waveforms: [UUID: [WaveformPeak]] = [:]

  init() {
    var store: SetStore?
    var loaded: [SoundSet] = []
    var loadError: String?
    do {
      // SOUNDBOARD_LIBRARY_DIR points the app at another library, e.g. a throwaway one
      // for end-to-end checks that must not touch the real sets.
      let directory =
        try ProcessInfo.processInfo.environment["SOUNDBOARD_LIBRARY_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? SetStore.defaultDirectory()
      let library = SetStore(directory: directory)
      store = library
      loaded = try library.loadAll()
    } catch {
      loadError = "Impossible d’ouvrir la bibliothèque de sons : \(error.localizedDescription)"
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
      self?.sendPlayingFeedback(for: [tileID])
    }
    osc.onCommand = { [weak self] command in self?.handleOSC(command) }
    engine.onAdvancePoint = { [weak self] tileID, lead in
      self?.advance(from: tileID, lead: lead)
    }
  }

  var soundSet: SoundSet { library.selectedSet }

  /// What the board shows: the selected set's own tiles, or for a smart set the matching
  /// tiles of ordinary sets. Hotkeys, MIDI and Play Selection act on these tiles.
  var shownSet: SoundSet { library.shownSet(soundSet, gridColumns: Self.gridColumns) }

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
      errorMessage = "Impossible de supprimer « \(set.title) » : \(error.localizedDescription)"
    }
  }

  /// Copies the shown set (plist and sounds) to a `.soundset` package at `destination`.
  func exportShownSet(to destination: URL) {
    do {
      guard let store else { throw BoardModelError.libraryUnavailable }
      try store.export(soundSet, to: destination)
    } catch {
      errorMessage = "Impossible d’exporter « \(soundSet.title) » : \(error.localizedDescription)"
    }
  }

  /// Opens sets from Finder, the Dock or a drop: a `.soundset` already in the library is shown
  /// instead of being duplicated; anything else is imported.
  func openSets(_ urls: [URL]) {
    importSets(from: urls, reusingSetsInLibrary: true)
  }

  /// Adds `.soundset` packages and Farrago `.farragoset` sets to the library and shows the
  /// last one imported. Problems are reported once all packages have been tried.
  func importSets(from urls: [URL], reusingSetsInLibrary: Bool = false) {
    var problems: [String] = []
    for url in urls {
      let name = url.lastPathComponent
      do {
        guard let store else { throw BoardModelError.libraryUnavailable }
        let set: SoundSet
        switch url.pathExtension.lowercased() {
        case SetStore.packageExtension:
          if reusingSetsInLibrary,
            let existing = library.set(withID: try store.setID(ofPackage: url))
          {
            selectSet(existing.id)
            continue
          }
          set = try store.importPackage(at: url)
        case "farragoset":
          let imported = try FarragoImport.read(package: url, packetDuration: SetFiles.seconds)
          set = try store.add(imported)
          if !imported.skippedTileTitles.isEmpty {
            problems.append(
              "\(name) : sons manquants pour \(imported.skippedTileTitles.joined(separator: ", "))"
            )
          }
        default:
          problems.append("\(name) : ni un .soundset ni un .farragoset")
          continue
        }
        library.add(set)
        rememberSelection()
      } catch {
        problems.append("\(name) : \(error.localizedDescription)")
      }
    }
    if !problems.isEmpty {
      errorMessage =
        "Certains sets n’ont pas pu être importés entièrement.\n" + problems.joined(separator: "\n")
    }
  }

  // MARK: Tiles

  /// Handles files dropped on the board: sets are opened, audio files become tiles.
  func drop(_ urls: [URL]) -> Bool {
    let sets = urls.filter { SetFiles.isSetPackage($0) }
    if !sets.isEmpty { openSets(sets) }
    let others = urls.filter { !SetFiles.isSetPackage($0) }
    let addedSounds = !others.isEmpty && addFiles(others)
    return addedSounds || !sets.isEmpty
  }

  /// Adds one tile per audio file to the shown set, copying the file into it;
  /// returns false if none were audio.
  @discardableResult
  func addFiles(_ urls: [URL]) -> Bool {
    guard !soundSet.isSmart else {
      errorMessage =
        "Un smart set se remplit selon ses règles : ajoutez les sons dans un set normal."
      return false
    }
    guard let store else {
      errorMessage = "Impossible d’ajouter des sons : la bibliothèque n’a pas pu être ouverte."
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
        errorMessage = "Impossible d’ajouter « \(tile.title) » : \(error.localizedDescription)"
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
    var edited = tile
    // A tile shown in a smart set carries that set's layout; its own set keeps its place.
    edited.gridPosition = set.tiles[index].gridPosition
    edited.listIndex = set.tiles[index].listIndex
    set.tiles[index] = edited
    library.replace(set)
    engine.update(edited)
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
      errorMessage =
        "Impossible de supprimer le son de « \(tile.title) » : \(error.localizedDescription)"
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
      errorMessage =
        "Impossible d’afficher la forme d’onde de « \(tile.title) » : \(error.localizedDescription)"
    }
  }

  /// Where playback is, in seconds into the whole file, while the tile sounds.
  func playbackPosition(of tile: Tile) -> TimeInterval? {
    engine.position(of: tile.id).map { tile.player.trimStart + $0 }
  }

  // MARK: Playback

  func press(_ tile: Tile, modifier: TriggerModifier, velocity: Float = 1) {
    selectedTileID = tile.id
    perform(
      coordinator.press(
        tile,
        modifier: modifier,
        listMode: isInListMode(tile),
        velocity: velocity
      )
    )
  }

  func release(_ tile: Tile) {
    perform(coordinator.release(tile, listMode: isInListMode(tile)))
  }

  /// Plays (or stops) the selected tile of the shown set, e.g. the one Cue next moved to.
  func playSelection() {
    guard let tile = selectedTile, shownSet.tiles.contains(where: { $0.id == tile.id }) else {
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
    guard let tile = shownSet.tile(forHotkey: key) else { return false }
    if isKeyDown {
      press(tile, modifier: shift ? .pause : .none)
    } else {
      release(tile)
    }
    return true
  }

  // MARK: OSC

  /// Runs a command received over OSC; tiles are found by set position and grid cell.
  func handleOSC(_ command: OSCCommand) {
    switch command {
    case .tile(let reference, let position, let action, let pressed):
      let set: SoundSet?
      switch reference {
      case .selected: set = shownSet
      case .index(let index):
        set =
          library.sets.indices.contains(index)
          ? library.shownSet(library.sets[index], gridColumns: Self.gridColumns) : nil
      }
      guard let tile = set?.tile(at: position) else { return }
      perform(action, on: tile, pressed: pressed)
    case .masterToggleAB: master.toggleAB()
    case .masterSelectVolumeA: master.usesVolumeB = false
    case .masterSelectVolumeB: master.usesVolumeB = true
    case .masterVolumeUp: master.stepUp()
    case .masterVolumeDown: master.stepDown()
    case .masterVolume(let volume): master.activeVolume = volume
    case .playPauseAll: togglePauseAll()
    case .stopAll: stopAll()
    case .bringForward: AppActivation.bringForward()
    }
  }

  private func perform(_ action: OSCCommand.TileAction, on tile: Tile, pressed: Bool) {
    if action == .play {
      if pressed { press(tile, modifier: .none) } else { release(tile) }
      return
    }
    guard pressed else { return }
    var updated = tile
    switch action {
    case .play: return
    case .fade:
      // Fades a playing tile out; an idle tile has nothing to fade.
      if coordinator.state(of: tile.id) != nil { press(tile, modifier: .fade) }
      return
    case .loop: updated.player.loops.toggle()
    case .mute: updated.player.muted.toggle()
    case .solo: updated.solo.toggle()
    case .toggleAB: updated.player.usesVolumeB.toggle()
    }
    update(updated)
  }

  /// Tells the OSC controller which of these tiles play, so it can light their buttons.
  private func sendPlayingFeedback(for tileIDs: [UUID]) {
    refreshMIDILights()
    guard osc.outputEnabled else { return }
    for tileID in Set(tileIDs) {
      guard let set = library.set(containingTile: tileID),
        let setIndex = library.sets.firstIndex(where: { $0.id == set.id }),
        let tile = set.tiles.first(where: { $0.id == tileID })
      else { continue }
      osc.send(
        OSCCommand.playingFeedback(
          setIndex: setIndex,
          position: tile.gridPosition,
          isPlaying: coordinator.state(of: tileID) == .playing
        )
      )
    }
  }

  // MARK: MIDI

  /// Tile waiting for the next note played on a controller (MIDI learn).
  var midiLearningTileID: UUID?
  /// Number of MIDI sources currently listened to, shown in the inspector.
  var midiSourceCount = 0

  /// The next note played on a controller will trigger the selected tile.
  func startMIDILearn() {
    midiLearningTileID = selectedTileID
  }

  func cancelMIDILearn() {
    midiLearningTileID = nil
  }

  func clearMIDI(for tile: Tile) {
    setMIDI(nil, for: tile)
  }

  /// Note-on plays the shown set's tile for that note, scaled by velocity; note-off releases
  /// Hold to Play tiles. While learning, the first note-on is given to the learning tile.
  func handleMIDI(_ message: MIDIMessage) {
    switch message {
    case .noteOn(let note, let velocity):
      if let learningID = midiLearningTileID,
        let tile = library.set(containingTile: learningID)?.tiles.first(where: {
          $0.id == learningID
        })
      {
        setMIDI(note, for: tile)
        midiLearningTileID = nil
        return
      }
      guard let tile = shownSet.tile(forMIDI: note) else { return }
      press(tile, modifier: .none, velocity: MIDIMessage.gain(forVelocity: velocity))
    case .noteOff(let note):
      guard let tile = shownSet.tile(forMIDI: note) else { return }
      release(tile)
    }
  }

  private func setMIDI(_ note: MIDINote?, for tile: Tile) {
    guard var set = library.set(containingTile: tile.id) else { return }
    set.assignMIDI(note, to: tile.id)
    library.replace(set)
    save(set)
    refreshMIDILights()
  }

  /// Lights the pads of the shown set's playing tiles; the shown set's notes are the ones the
  /// controller triggers, so switching sets relights the pads.
  private func refreshMIDILights() {
    let playing = shownSet.tiles.filter { coordinator.state(of: $0.id) == .playing }
    midiOutput.show(Set(playing.compactMap(\.midiTrigger)))
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
    defer { sendPlayingFeedback(for: commands.map(\.tileID)) }
    for command in commands {
      switch command {
      case .start(let tileID, let fadeIn, let velocity):
        start(tileID, fadeIn: fadeIn, velocity: velocity)
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

  private func start(_ tileID: UUID, fadeIn: TimeInterval, velocity: Float) {
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
        velocity: velocity,
        continuousCrossfade: set.continuousCrossfade
      )
    } catch {
      coordinator.voiceDidFinish(tileID)
      errorMessage = "Impossible de lire « \(tile.title) » : \(error.localizedDescription)"
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
    guard !soundSet.isSmart, tileID != targetID,
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
    // Through update() so a smart set clears the marks of the tiles it shows.
    for tile in shownSet.tiles where tile.lastPlayed != nil {
      var cleared = tile
      cleared.lastPlayed = nil
      update(cleared)
    }
    selectedTileID = shownSet.firstPlayableTile?.id
  }

  // MARK: Smart sets

  /// Set whose rules are being edited in the rule editor sheet.
  var rulesEditorSetID: UUID?

  /// Adds a smart set showing favourite tiles and opens its rules.
  func addSmartSet() {
    var set = library.addSet()
    set.title = "Smart set"
    set.smartRules = SmartRules()
    library.replace(set)
    rememberSelection()
    save(set)
    rulesEditorSetID = set.id
  }

  func setRules(_ rules: SmartRules, forSet setID: UUID) {
    guard var set = library.set(withID: setID), set.isSmart else { return }
    set.smartRules = rules
    library.replace(set)
    save(set)
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
      errorMessage = "Impossible d’enregistrer « \(set.title) » : \(error.localizedDescription)"
    }
  }

  private func saveMaster() {
    do {
      UserDefaults.standard.set(try JSONEncoder().encode(master), forKey: Self.masterVolumeKey)
    } catch {
      errorMessage = "Impossible d’enregistrer le volume général : \(error.localizedDescription)"
    }
  }

  /// A missing or unreadable preference falls back to the defaults (A 100 %, B 40 %).
  private static func loadMaster() -> MasterVolume {
    guard let data = UserDefaults.standard.data(forKey: masterVolumeKey),
      let master = try? JSONDecoder().decode(MasterVolume.self, from: data)
    else { return MasterVolume() }
    return master
  }

  /// Called on every change of the shown set.
  private func rememberSelection() {
    UserDefaults.standard.set(library.selectedSetID.uuidString, forKey: Self.selectedSetKey)
    refreshMIDILights()
  }
}

enum BoardModelError: LocalizedError {
  case libraryUnavailable

  var errorDescription: String? {
    switch self {
    case .libraryUnavailable: "La bibliothèque de sons n’a pas pu être ouverte."
    }
  }
}

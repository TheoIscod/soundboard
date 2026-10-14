import Foundation
import Testing

@testable import SoundboardCore

/// A list set whose tiles A, B, C, D are in that list order.
private func makeListSet(mode: PlaybackMode, crossfade: TimeInterval = 0) -> SoundSet {
  var set = SoundSet(title: "Show")
  set.displayMode = .list
  set.playbackMode = mode
  set.crossfadeDuration = crossfade
  for (index, title) in ["A", "B", "C", "D"].enumerated() {
    var tile = Tile(fileID: UUID(), originalFileName: "\(title).m4a", title: title)
    tile.listIndex = index
    // Grid order is the reverse, so a test fails if it uses the wrong order.
    tile.gridPosition = GridPosition(column: 3 - index, row: 0)
    set.tiles.append(tile)
  }
  return set
}

private func tile(_ title: String, in set: SoundSet) -> Tile {
  set.tiles.first { $0.title == title }!
}

@Test func displayOrderFollowsTheDisplayMode() {
  var set = makeListSet(mode: .single)
  #expect(set.displayOrder.map(\.title) == ["A", "B", "C", "D"])

  set.displayMode = .grid
  #expect(set.displayOrder.map(\.title) == ["D", "C", "B", "A"])
}

@Test func equalListIndicesFallBackToGridOrder() {
  var set = SoundSet(title: "Old")
  for column in [1, 0] {
    var tile = Tile(fileID: UUID(), originalFileName: "t.m4a", title: "\(column)")
    tile.gridPosition = GridPosition(column: column, row: 0)
    set.tiles.append(tile)
  }
  #expect(set.listOrder.map(\.title) == ["0", "1"])
  #expect(set.nextListIndex == 1)
}

@Test func nextPlayableTileSkipsDisabledTilesAndDoesNotWrap() {
  var set = makeListSet(mode: .toggle)
  set.tiles[1].isEnabled = false

  #expect(set.nextPlayableTile(after: tile("A", in: set).id)?.title == "C")
  #expect(set.nextPlayableTile(after: tile("D", in: set).id) == nil)
  #expect(set.firstPlayableTile?.title == "A")
}

@Test func cueNextOnlyActsInListToggleMode() {
  var set = makeListSet(mode: .toggle)
  let first = tile("A", in: set).id
  #expect(set.tileToCue(afterStopping: first)?.title == "B")

  set.playbackMode = .continuous
  #expect(set.tileToCue(afterStopping: first) == nil)

  set.playbackMode = .toggle
  set.displayMode = .grid
  #expect(set.tileToCue(afterStopping: first) == nil)
}

@Test func continuousCrossfadeOnlyInListMode() {
  var set = makeListSet(mode: .continuous, crossfade: 3)
  #expect(set.continuousCrossfade == 3)

  set.displayMode = .grid
  #expect(set.continuousCrossfade == nil)
}

@Test func crossfadeLeadIsCappedAtHalfTheSound() {
  #expect(SoundSet.crossfadeLead(crossfade: 3, soundLength: 10) == 3)
  #expect(SoundSet.crossfadeLead(crossfade: 3, soundLength: 4) == 2)
  #expect(SoundSet.crossfadeLead(crossfade: 0, soundLength: 4) == 0)
}

@Test func crossfadeFadesOutgoingAndFadesInNext() {
  var coordinator = PlaybackCoordinator()
  let set = makeListSet(mode: .continuous, crossfade: 2)
  let first = tile("A", in: set)
  let second = tile("B", in: set)
  _ = coordinator.press(first, listMode: true)

  #expect(
    coordinator.crossfade(from: first, to: second, duration: 2)
      == [.stop(first.id, fade: 2), .start(second.id, fadeIn: 2)]
  )
  #expect(coordinator.state(of: first.id) == nil)
  #expect(coordinator.state(of: second.id) == .playing)
}

@Test func loopingOutgoingTileKeepsPlayingUnderTheNext() {
  var coordinator = PlaybackCoordinator()
  var set = makeListSet(mode: .continuous)
  set.tiles[0].player.loops = true
  let first = tile("A", in: set)
  let second = tile("B", in: set)
  _ = coordinator.press(first, listMode: true)

  #expect(coordinator.crossfade(from: first, to: second, duration: 0) == [.start(second.id)])
  #expect(coordinator.state(of: first.id) == .playing)
}

@Test func crossfadeDoesNotRestartATileAlreadyPlaying() {
  var coordinator = PlaybackCoordinator()
  let set = makeListSet(mode: .continuous)
  let first = tile("A", in: set)
  let second = tile("B", in: set)
  _ = coordinator.press(first, listMode: true)
  _ = coordinator.press(second, listMode: true)

  #expect(coordinator.crossfade(from: first, to: second, duration: 1) == [])
}

@Test func listModeIgnoresSoloAndHoldToPlay() {
  var coordinator = PlaybackCoordinator()
  var set = makeListSet(mode: .single)
  set.tiles[0].solo = true
  set.tiles[1].holdToPlay = true
  let solo = tile("A", in: set)
  let hold = tile("B", in: set)

  _ = coordinator.press(hold, listMode: true)
  #expect(coordinator.release(hold, listMode: true) == [])
  #expect(coordinator.press(solo, listMode: true) == [.start(solo.id)])
  #expect(coordinator.state(of: hold.id) == .playing)
}

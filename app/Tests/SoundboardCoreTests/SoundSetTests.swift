import Foundation
import Testing

@testable import SoundboardCore

@Test func newSetDefaultsMatchSpec() {
  let set = SoundSet(title: "Test")

  #expect(set.displayMode == .grid)
  #expect(set.playbackMode == .toggle)
  #expect(set.tiles.isEmpty)
}

@Test func activeVolumeFollowsVolumeBFlag() {
  var settings = PlayerSettings()
  #expect(settings.activeVolume == 1.0)

  settings.usesVolumeB = true
  #expect(settings.activeVolume == 0.4)
}

@Test func newTilesFillTheFirstFreeGridCell() {
  var set = SoundSet(title: "Grid")
  #expect(set.nextFreeGridPosition(columns: 3) == GridPosition(column: 0, row: 0))

  for column in [0, 2] {
    var tile = Tile(fileID: UUID(), originalFileName: "a.m4a", title: "a")
    tile.gridPosition = GridPosition(column: column, row: 0)
    set.tiles.append(tile)
  }
  #expect(set.nextFreeGridPosition(columns: 3) == GridPosition(column: 1, row: 0))

  var middle = Tile(fileID: UUID(), originalFileName: "b.m4a", title: "b")
  middle.gridPosition = GridPosition(column: 1, row: 0)
  set.tiles.append(middle)
  #expect(set.nextFreeGridPosition(columns: 3) == GridPosition(column: 0, row: 1))
}

@Test func soundSetRoundTripsThroughPropertyList() throws {
  var set = SoundSet(title: "Effects")
  var tile = Tile(fileID: UUID(), originalFileName: "Dog Bark.m4a", title: "Dog Bark")
  tile.icon = "🐕"
  tile.player.loops = true
  tile.player.trimStart = 0.25
  set.tiles.append(tile)
  set.playbackMode = .continuous

  let data = try PropertyListEncoder().encode(set)
  let decoded = try PropertyListDecoder().decode(SoundSet.self, from: data)

  #expect(decoded == set)
}

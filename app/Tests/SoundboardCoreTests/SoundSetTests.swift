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

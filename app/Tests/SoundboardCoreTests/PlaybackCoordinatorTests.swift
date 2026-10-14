import Foundation
import Testing

@testable import SoundboardCore

private func makeTile(_ title: String = "Tile") -> Tile {
  Tile(fileID: UUID(), originalFileName: "\(title).m4a", title: title)
}

@Test func pressTogglesBetweenPlayingAndStopped() {
  var coordinator = PlaybackCoordinator()
  let tile = makeTile()

  #expect(coordinator.press(tile) == [.start(tile.id)])
  #expect(coordinator.state(of: tile.id) == .playing)

  #expect(coordinator.press(tile) == [.stop(tile.id, fade: nil)])
  #expect(coordinator.state(of: tile.id) == nil)
}

@Test func startingATileLeavesOthersPlaying() {
  var coordinator = PlaybackCoordinator()
  let first = makeTile("First")
  let second = makeTile("Second")

  _ = coordinator.press(first)
  #expect(coordinator.press(second) == [.start(second.id)])
  #expect(coordinator.state(of: first.id) == .playing)
}

@Test func soloTileStopsEveryOtherSoundImmediately() {
  var coordinator = PlaybackCoordinator()
  let other = makeTile("Other")
  var solo = makeTile("Solo")
  solo.solo = true

  _ = coordinator.press(other)
  #expect(coordinator.press(solo) == [.stop(other.id, fade: nil), .start(solo.id)])
  #expect(coordinator.state(of: other.id) == nil)
}

@Test func fadeModifierFadesTheSoundsASoloTileStops() {
  var coordinator = PlaybackCoordinator()
  coordinator.fadeTime = 3
  let other = makeTile("Other")
  var solo = makeTile("Solo")
  solo.solo = true

  _ = coordinator.press(other)
  #expect(coordinator.press(solo, modifier: .fade) == [.stop(other.id, fade: 3), .start(solo.id)])
}

@Test func fadeModifierStopsAPlayingTileWithTheGlobalFadeTime() {
  var coordinator = PlaybackCoordinator()
  let tile = makeTile()

  _ = coordinator.press(tile)
  #expect(coordinator.press(tile, modifier: .fade) == [.stop(tile.id, fade: 2)])
}

@Test func pauseModifierPausesAndNextPressResumes() {
  var coordinator = PlaybackCoordinator()
  let tile = makeTile()

  _ = coordinator.press(tile)
  #expect(coordinator.press(tile, modifier: .pause) == [.pause(tile.id)])
  #expect(coordinator.state(of: tile.id) == .paused)

  #expect(coordinator.press(tile) == [.resume(tile.id)])
  #expect(coordinator.state(of: tile.id) == .playing)
}

@Test func holdToPlayStartsOnPressAndStopsOnRelease() {
  var coordinator = PlaybackCoordinator()
  var tile = makeTile()
  tile.holdToPlay = true

  #expect(coordinator.press(tile) == [.start(tile.id)])
  #expect(coordinator.press(tile) == [])
  #expect(coordinator.release(tile) == [.stop(tile.id, fade: nil)])
  #expect(coordinator.state(of: tile.id) == nil)
}

@Test func releaseIgnoresRegularTiles() {
  var coordinator = PlaybackCoordinator()
  let tile = makeTile()

  _ = coordinator.press(tile)
  #expect(coordinator.release(tile) == [])
  #expect(coordinator.state(of: tile.id) == .playing)
}

@Test func disabledTileCannotBeTriggered() {
  var coordinator = PlaybackCoordinator()
  var tile = makeTile()
  tile.isEnabled = false

  #expect(coordinator.press(tile) == [])
}

@Test func finishedVoiceIsNoLongerPlaying() {
  var coordinator = PlaybackCoordinator()
  let tile = makeTile()

  _ = coordinator.press(tile)
  coordinator.voiceDidFinish(tile.id)
  #expect(coordinator.state(of: tile.id) == nil)
  #expect(coordinator.press(tile) == [.start(tile.id)])
}

@Test func stopAllAndFadeOutAllClearEveryVoice() {
  var coordinator = PlaybackCoordinator()
  let first = makeTile("First")
  let second = makeTile("Second")
  _ = coordinator.press(first)
  _ = coordinator.press(second)

  let fades = coordinator.fadeOutAll()
  #expect(fades.count == 2)
  #expect(fades.allSatisfy { if case .stop(_, fade: 2) = $0 { true } else { false } })
  #expect(coordinator.states.isEmpty)

  _ = coordinator.press(first)
  #expect(coordinator.stopAll() == [.stop(first.id, fade: nil)])
}

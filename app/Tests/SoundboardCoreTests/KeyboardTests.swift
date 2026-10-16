import Foundation
import Testing

@testable import SoundboardCore

private func makeTile(_ title: String) -> Tile {
  Tile(fileID: UUID(), originalFileName: "\(title).m4a", title: title)
}

@Test func hotkeysAreSingleLowercasedLettersOrDigits() {
  #expect(Hotkey.normalized("A") == "a")
  #expect(Hotkey.normalized("7") == "7")
  #expect(Hotkey.normalized("ab") == nil)
  #expect(Hotkey.normalized("é") == nil)
  #expect(Hotkey.normalized(" ") == nil)
  #expect(Hotkey.normalized("-") == nil)
  #expect(Hotkey.normalized("") == nil)
}

@Test func assigningAHotkeyTakesItFromTheOtherTile() {
  var set = SoundSet(title: "Keys")
  let first = makeTile("First")
  let second = makeTile("Second")
  set.tiles = [first, second]

  set.assignHotkey("Q", to: first.id)
  #expect(set.tile(forHotkey: "q")?.id == first.id)

  set.assignHotkey("q", to: second.id)
  #expect(set.tile(forHotkey: "Q")?.id == second.id)
  #expect(set.tiles[0].hotkey == nil)

  set.assignHotkey(nil, to: second.id)
  #expect(set.tile(forHotkey: "q") == nil)
}

@Test func tilesWithoutAHotkeyDecodeFromOlderSets() throws {
  let tile = makeTile("Old")
  var plist =
    try PropertyListSerialization.propertyList(
      from: PropertyListEncoder().encode(tile),
      format: nil
    ) as! [String: Any]
  plist.removeValue(forKey: "hotkey")
  let data = try PropertyListSerialization.data(
    fromPropertyList: plist, format: .binary, options: 0)

  #expect(try PropertyListDecoder().decode(Tile.self, from: data).hotkey == nil)
}

@Test func pauseAllPausesPlayingSoundsThenResumesThem() {
  var coordinator = PlaybackCoordinator()
  let first = makeTile("First")
  let second = makeTile("Second")
  _ = coordinator.press(first)
  _ = coordinator.press(second)

  let paused = coordinator.togglePauseAll()
  #expect(paused.count == 2)
  #expect(paused.allSatisfy { if case .pause = $0 { true } else { false } })
  #expect(coordinator.state(of: first.id) == .paused)

  let resumed = coordinator.togglePauseAll()
  #expect(resumed.allSatisfy { if case .resume = $0 { true } else { false } })
  #expect(coordinator.state(of: second.id) == .playing)
}

@Test func pauseAllOnlyPausesWhileSomethingPlays() {
  var coordinator = PlaybackCoordinator()
  let playing = makeTile("Playing")
  let paused = makeTile("Paused")
  _ = coordinator.press(playing)
  _ = coordinator.press(paused)
  _ = coordinator.press(paused, modifier: .pause)

  #expect(coordinator.togglePauseAll() == [.pause(playing.id)])
  #expect(coordinator.togglePauseAll().count == 2)
}

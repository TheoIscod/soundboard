import Foundation
import Testing

@testable import SoundboardCore

private func tile(_ title: String, configure: (inout Tile) -> Void = { _ in }) -> Tile {
  var tile = Tile(fileID: UUID(), originalFileName: "\(title).m4a", title: title)
  configure(&tile)
  return tile
}

@Test func titleRulesIgnoreCaseAndAccents() {
  let applause = tile("Applaudissements Été")

  #expect(SmartRule.title(.contains, "ete").matches(applause))
  #expect(SmartRule.title(.beginsWith, "APPLAU").matches(applause))
  #expect(SmartRule.title(.endsWith, "été").matches(applause))
  #expect(!SmartRule.title(.beginsWith, "été").matches(applause))
  #expect(!SmartRule.title(.contains, "  ").matches(applause))
}

@Test func flagAndColorRulesReadTheTile() {
  let favourite = tile("Fav") {
    $0.isFavorite = true
    $0.color = .green
    $0.lastPlayed = Date()
  }

  #expect(SmartRule.flag(.favorite, is: true).matches(favourite))
  #expect(SmartRule.flag(.played, is: true).matches(favourite))
  #expect(SmartRule.flag(.loops, is: false).matches(favourite))
  #expect(SmartRule.color(.green).matches(favourite))
  #expect(!SmartRule.color(.red).matches(favourite))
}

@Test func allNeedsEveryRuleAndAnyNeedsOne() {
  let looping = tile("Loop") { $0.player.loops = true }
  let rules = [SmartRule.flag(.loops, is: true), .flag(.favorite, is: true)]

  #expect(!SmartRules(match: .all, rules: rules).matches(looping))
  #expect(SmartRules(match: .any, rules: rules).matches(looping))
  #expect(!SmartRules(match: .any, rules: []).matches(looping))
}

@Test func smartSetShowsMatchingTilesOfOrdinarySetsInOrder() {
  var effects = SoundSet(title: "A Effects")
  effects.tiles = [
    tile("Bark") {
      $0.isFavorite = true
      $0.gridPosition = GridPosition(column: 1, row: 0)
    },
    tile("Meow") {
      $0.isFavorite = true
      $0.gridPosition = GridPosition(column: 0, row: 0)
    },
    tile("Moo"),
  ]
  var music = SoundSet(title: "B Music")
  music.tiles = [tile("Anthem") { $0.isFavorite = true }]
  var favourites = SoundSet(title: "C Favourites")
  favourites.smartRules = SmartRules()
  let library = SoundLibrary(sets: [effects, music, favourites])

  let shown = library.shownSet(favourites, gridColumns: 2)

  #expect(shown.tiles.map(\.title) == ["Meow", "Bark", "Anthem"])
  #expect(
    shown.tiles.map(\.gridPosition) == [
      GridPosition(column: 0, row: 0), GridPosition(column: 1, row: 0),
      GridPosition(column: 0, row: 1),
    ])
  #expect(shown.tiles[0].id == effects.tiles[1].id)
  #expect(library.shownSet(effects, gridColumns: 2) == effects)
}

@Test func smartRulesSurviveSavingAndOlderSetsDecodeWithout() throws {
  var smart = SoundSet(title: "Smart")
  smart.smartRules = SmartRules(match: .any, rules: [.title(.contains, "x"), .color(.pink)])
  let data = try PropertyListEncoder().encode(smart)
  #expect(try PropertyListDecoder().decode(SoundSet.self, from: data) == smart)

  var plist =
    try PropertyListSerialization.propertyList(
      from: PropertyListEncoder().encode(SoundSet(title: "Old")), format: nil) as! [String: Any]
  plist.removeValue(forKey: "smartRules")
  let old = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
  #expect(try PropertyListDecoder().decode(SoundSet.self, from: old).smartRules == nil)
}

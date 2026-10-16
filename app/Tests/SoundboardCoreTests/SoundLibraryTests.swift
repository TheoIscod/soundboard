import Foundation
import Testing

@testable import SoundboardCore

@Test func emptyLibraryStartsWithOneUntitledSet() {
  let library = SoundLibrary(sets: [])

  #expect(library.sets.map(\.title) == ["Set sans titre"])
  #expect(library.selectedSet.id == library.sets[0].id)
}

@Test func setsAreOrderedByTitleAndUnknownSelectionFallsBackToFirst() {
  let library = SoundLibrary(
    sets: [SoundSet(title: "Music"), SoundSet(title: "Effects 10"), SoundSet(title: "Effects 2")],
    selectedSetID: UUID()
  )

  #expect(library.sets.map(\.title) == ["Effects 2", "Effects 10", "Music"])
  #expect(library.selectedSet.title == "Effects 2")
}

@Test func newSetsGetUniqueNamesAndBecomeSelected() {
  var library = SoundLibrary(sets: [])

  let second = library.addSet()
  let third = library.addSet()

  #expect(second.title == "Set sans titre 2")
  #expect(third.title == "Set sans titre 3")
  #expect(library.selectedSetID == third.id)
}

@Test func renamingReordersTheList() {
  var library = SoundLibrary(sets: [SoundSet(title: "A"), SoundSet(title: "B")])
  var renamed = library.sets[0]
  renamed.title = "C"

  library.replace(renamed)

  #expect(library.sets.map(\.title) == ["B", "C"])
}

@Test func removingTheShownSetShowsTheNextOne() {
  var library = SoundLibrary(sets: [
    SoundSet(title: "A"), SoundSet(title: "B"), SoundSet(title: "C"),
  ])
  library.select(library.sets[1].id)

  let removedFirst = library.removeSet(library.selectedSetID)
  #expect(removedFirst)
  #expect(library.selectedSet.title == "C")

  let removedSecond = library.removeSet(library.selectedSetID)
  #expect(removedSecond)
  #expect(library.selectedSet.title == "A")
}

@Test func lastSetCannotBeRemoved() {
  var library = SoundLibrary(sets: [])

  let removed = library.removeSet(library.selectedSetID)
  #expect(!removed)
  #expect(library.sets.count == 1)
}

@Test func nextAndPreviousStopAtTheEnds() {
  var library = SoundLibrary(sets: [SoundSet(title: "A"), SoundSet(title: "B")])

  library.selectPreviousSet()
  #expect(library.selectedSet.title == "A")
  library.selectNextSet()
  #expect(library.selectedSet.title == "B")
  library.selectNextSet()
  #expect(library.selectedSet.title == "B")
}

@Test func tilesAreFoundInSetsThatAreNotShown() {
  var effects = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  effects.tiles.append(tile)
  let library = SoundLibrary(sets: [effects, SoundSet(title: "Music")])

  #expect(library.set(containingTile: tile.id)?.id == effects.id)
}

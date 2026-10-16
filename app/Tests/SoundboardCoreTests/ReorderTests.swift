import Foundation
import Testing

@testable import SoundboardCore

/// Tiles A, B, C, D in that order in both the grid (2 columns) and the list.
private func makeSet(displayMode: DisplayMode) -> SoundSet {
  var set = SoundSet(title: "Reorder")
  set.displayMode = displayMode
  for (index, title) in ["A", "B", "C", "D"].enumerated() {
    var tile = Tile(fileID: UUID(), originalFileName: "\(title).m4a", title: title)
    tile.listIndex = index
    tile.gridPosition = GridPosition(column: index % 2, row: index / 2)
    set.tiles.append(tile)
  }
  return set
}

private func id(_ title: String, in set: SoundSet) -> UUID {
  set.tiles.first { $0.title == title }!.id
}

@Test func movingDownPlacesTheTileAtTheTargetIndex() {
  var set = makeSet(displayMode: .list)
  set.moveTile(id("A", in: set), to: 2, gridColumns: 2)

  #expect(set.listOrder.map(\.title) == ["B", "C", "A", "D"])
}

@Test func movingUpAndPastTheEndAreHandled() {
  var set = makeSet(displayMode: .list)
  set.moveTile(id("D", in: set), to: 0, gridColumns: 2)
  #expect(set.listOrder.map(\.title) == ["D", "A", "B", "C"])

  set.moveTile(id("D", in: set), to: 99, gridColumns: 2)
  #expect(set.listOrder.map(\.title) == ["A", "B", "C", "D"])
}

@Test func listMovesLeaveTheGridUntouched() {
  var set = makeSet(displayMode: .list)
  set.moveTile(id("A", in: set), to: 3, gridColumns: 2)

  set.displayMode = .grid
  #expect(set.gridOrder.map(\.title) == ["A", "B", "C", "D"])
}

@Test func gridMovesRewriteCellsAndPackGaps() {
  var set = makeSet(displayMode: .grid)
  set.tiles.removeAll { $0.title == "B" }

  set.moveTile(id("D", in: set), to: 0, gridColumns: 2)

  #expect(set.gridOrder.map(\.title) == ["D", "A", "C"])
  #expect(
    set.gridOrder.map(\.gridPosition) == [
      GridPosition(column: 0, row: 0), GridPosition(column: 1, row: 0),
      GridPosition(column: 0, row: 1),
    ])
  set.displayMode = .list
  #expect(set.listOrder.map(\.title) == ["A", "C", "D"])
}

import Foundation

/// All sound sets plus which one is shown. Sets are ordered by title.
public struct SoundLibrary: Sendable, Equatable {
  public static let defaultSetTitle = "Set sans titre"

  public private(set) var sets: [SoundSet]
  public private(set) var selectedSetID: UUID

  /// Never empty: an empty library gets one untitled set.
  public init(sets: [SoundSet], selectedSetID: UUID? = nil) {
    let sets = sets.isEmpty ? [SoundSet(title: Self.defaultSetTitle)] : sets
    self.sets = sets.sorted(by: Self.order)
    self.selectedSetID =
      selectedSetID.flatMap { id in sets.contains { $0.id == id } ? id : nil }
      ?? self.sets[0].id
  }

  public var selectedSet: SoundSet {
    get { sets.first { $0.id == selectedSetID } ?? sets[0] }
    set { replace(newValue) }
  }

  public func set(withID id: UUID) -> SoundSet? {
    sets.first { $0.id == id }
  }

  /// The set holding a tile, for playing tiles of sets that are not shown.
  public func set(containingTile tileID: UUID) -> SoundSet? {
    sets.first { set in set.tiles.contains { $0.id == tileID } }
  }

  public mutating func select(_ id: UUID) {
    guard sets.contains(where: { $0.id == id }) else { return }
    selectedSetID = id
  }

  /// Adds and selects a new empty set named "Set sans titre", "Set sans titre 2", …
  @discardableResult
  public mutating func addSet() -> SoundSet {
    let titles = Set(sets.map(\.title))
    var title = Self.defaultSetTitle
    var number = 2
    while titles.contains(title) {
      title = "\(Self.defaultSetTitle) \(number)"
      number += 1
    }
    let set = SoundSet(title: title)
    sets.append(set)
    sets.sort(by: Self.order)
    selectedSetID = set.id
    return set
  }

  /// Adds an existing set, e.g. an imported one, and shows it.
  public mutating func add(_ set: SoundSet) {
    guard !sets.contains(where: { $0.id == set.id }) else { return }
    sets.append(set)
    sets.sort(by: Self.order)
    selectedSetID = set.id
  }

  public mutating func replace(_ set: SoundSet) {
    guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
    sets[index] = set
    sets.sort(by: Self.order)
  }

  /// Removes a set; the last remaining set cannot be removed.
  /// When the shown set goes, the one that took its place in the list is shown.
  @discardableResult
  public mutating func removeSet(_ id: UUID) -> Bool {
    guard sets.count > 1, let index = sets.firstIndex(where: { $0.id == id }) else { return false }
    sets.remove(at: index)
    if selectedSetID == id {
      selectedSetID = sets[min(index, sets.count - 1)].id
    }
    return true
  }

  public mutating func selectNextSet() {
    moveSelection(by: 1)
  }

  public mutating func selectPreviousSet() {
    moveSelection(by: -1)
  }

  private mutating func moveSelection(by offset: Int) {
    guard let index = sets.firstIndex(where: { $0.id == selectedSetID }) else { return }
    let target = index + offset
    guard sets.indices.contains(target) else { return }
    selectedSetID = sets[target].id
  }

  private static func order(_ lhs: SoundSet, _ rhs: SoundSet) -> Bool {
    let comparison = lhs.title.localizedStandardCompare(rhs.title)
    return comparison == .orderedSame
      ? lhs.id.uuidString < rhs.id.uuidString
      : comparison == .orderedAscending
  }
}

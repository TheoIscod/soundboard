import Foundation
import Testing

@testable import SoundboardCore

private func makeStore() -> SetStore {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "SetStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  return SetStore(directory: directory)
}

@Test func emptyLibraryLoadsNoSets() throws {
  #expect(try makeStore().loadAll().isEmpty)
}

@Test func savedSetLoadsBackIdentically() throws {
  let store = makeStore()
  var set = SoundSet(title: "Effects")
  set.tiles.append(Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark"))

  try store.save(set)
  #expect(try store.loadAll() == [set])

  set.title = "Renamed"
  try store.save(set)
  #expect(try store.loadAll() == [set])
}

@Test func importedSoundIsCopiedIntoThePackage() throws {
  let store = makeStore()
  let set = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
  try Data("audio".utf8).write(to: source)

  try store.importSound(from: source, for: tile, in: set.id)
  try FileManager.default.removeItem(at: source)

  let copy = store.soundURL(for: tile, in: set.id)
  #expect(copy.lastPathComponent == "\(tile.fileID.uuidString).m4a")
  #expect(try Data(contentsOf: copy) == Data("audio".utf8))
}

@Test func setFromANewerFormatIsRejected() throws {
  let store = makeStore()
  var set = SoundSet(title: "Future")
  set.formatVersion = SoundSet.formatVersion + 1
  try store.save(set)

  #expect(throws: SetStoreError.newerFormat("Future", version: SoundSet.formatVersion + 1)) {
    try store.loadAll()
  }
}

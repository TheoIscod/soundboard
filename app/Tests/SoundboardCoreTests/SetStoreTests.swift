import Foundation
import Testing

@testable import SoundboardCore

private func makeStore() -> SetStore {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "SetStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  return SetStore(directory: directory)
}

@Test func emptyLibraryLoadsNoSets() throws {
  #expect(try makeStore().loadAll().sets.isEmpty)
}

@Test func savedSetLoadsBackIdentically() throws {
  let store = makeStore()
  var set = SoundSet(title: "Effects")
  set.tiles.append(Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark"))

  try store.save(set)
  #expect(try store.loadAll().sets == [set])

  set.title = "Renamed"
  try store.save(set)
  #expect(try store.loadAll().sets == [set])
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

@Test func removedSoundDeletesOnlyThatCopy() throws {
  let store = makeStore()
  let set = SoundSet(title: "Effects")
  let kept = Tile(fileID: UUID(), originalFileName: "Kept.m4a", title: "Kept")
  let removed = Tile(fileID: UUID(), originalFileName: "Removed.m4a", title: "Removed")
  let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
  try Data("audio".utf8).write(to: source)
  try store.importSound(from: source, for: kept, in: set.id)
  try store.importSound(from: source, for: removed, in: set.id)

  try store.removeSound(for: removed, in: set.id)
  try store.removeSound(for: removed, in: set.id)

  #expect(!FileManager.default.fileExists(atPath: store.soundURL(for: removed, in: set.id).path))
  #expect(FileManager.default.fileExists(atPath: store.soundURL(for: kept, in: set.id).path))
}

@Test func deletedSetIsGoneWithItsSounds() throws {
  let store = makeStore()
  let set = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
  try Data("audio".utf8).write(to: source)
  try store.save(set)
  try store.importSound(from: source, for: tile, in: set.id)

  try store.delete(set.id)

  #expect(try store.loadAll().sets.isEmpty)
  #expect(!FileManager.default.fileExists(atPath: store.soundURL(for: tile, in: set.id).path))
}

@Test func unreadableSetsAreReportedWithoutHidingTheOthers() throws {
  let store = makeStore()
  var future = SoundSet(title: "Future")
  future.formatVersion = SoundSet.formatVersion + 1
  try store.save(future)
  let healthy = SoundSet(title: "Healthy")
  try store.save(healthy)

  let contents = try store.loadAll()

  #expect(contents.sets == [healthy])
  #expect(contents.unreadable.count == 1)
  #expect(contents.unreadable[0].contains("Future"))
}

@Test func droppedLinksAreCopiedAsTheRealFile() throws {
  let store = makeStore()
  let set = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let real = folder.appending(path: "real.m4a")
  try Data("bark".utf8).write(to: real)
  let link = folder.appending(path: "link.m4a")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

  try store.importSound(from: link, for: tile, in: set.id)

  let copy = store.soundURL(for: tile, in: set.id)
  #expect(try copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
  #expect(try Data(contentsOf: copy) == Data("bark".utf8))
}

@Test func savedWaveformsAreFoundByResolutionAndRemovedWithTheSound() throws {
  let store = makeStore()
  let set = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  let peaks = [WaveformPeak(low: -1, high: 1)]

  #expect(store.savedWaveform(for: tile, in: set.id, binCount: 600) == nil)
  try store.saveWaveform(peaks, for: tile, in: set.id, binCount: 600)
  #expect(store.savedWaveform(for: tile, in: set.id, binCount: 600) == peaks)
  #expect(store.savedWaveform(for: tile, in: set.id, binCount: 1200) == nil)

  try store.removeSound(for: tile, in: set.id)
  #expect(store.savedWaveform(for: tile, in: set.id, binCount: 600) == nil)
}

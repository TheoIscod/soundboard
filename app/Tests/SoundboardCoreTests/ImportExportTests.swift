import Foundation
import Testing

@testable import SoundboardCore

private func temporaryDirectory(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func writeSound(_ text: String, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try Data(text.utf8).write(to: url)
}

@Test func addedSetIsShownAndKeptInOrder() {
  var library = SoundLibrary(sets: [SoundSet(title: "B")])
  let imported = SoundSet(title: "A")

  library.add(imported)

  #expect(library.sets.map(\.title) == ["A", "B"])
  #expect(library.selectedSetID == imported.id)
}

@Test func exportedPackageImportsAsAnIndependentCopy() throws {
  let store = SetStore(directory: temporaryDirectory("Library"))
  var set = SoundSet(title: "Effects")
  let tile = Tile(fileID: UUID(), originalFileName: "Bark.m4a", title: "Bark")
  set.tiles.append(tile)
  let source = temporaryDirectory("Source").appending(path: "Bark.m4a")
  try writeSound("bark", to: source)
  try store.importSound(from: source, for: tile, in: set.id)
  let exported = temporaryDirectory("Export").appending(path: "Effects.soundset")
  try FileManager.default.createDirectory(
    at: exported.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  try store.export(set, to: exported)
  let first = try store.importPackage(at: exported)
  let second = try store.importPackage(at: exported)

  #expect(first.id != set.id && second.id != first.id)
  #expect(first.tiles[0].id != tile.id)
  #expect(first.tiles[0].title == "Bark")
  #expect(
    try Data(contentsOf: store.soundURL(for: first.tiles[0], in: first.id)) == Data("bark".utf8))
  #expect(try store.loadAll().sets.count == 3)
}

@Test func exportedPackageKeepsTheSetIDForOpening() throws {
  let store = SetStore(directory: temporaryDirectory("Library"))
  let set = SoundSet(title: "Effects")
  let exported = temporaryDirectory("Export").appending(path: "Effects.soundset")
  try FileManager.default.createDirectory(
    at: exported.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  try store.export(set, to: exported)

  #expect(try store.setID(ofPackage: exported) == set.id)
}

@Test func farragoSetMapsSettingsAndSkipsTilesWithoutSound() throws {
  let package = temporaryDirectory("Farrago").appending(path: "Show.farragoset")
  let fileID = UUID()
  try writeSound("dog", to: package.appending(path: "Sound Files/\(fileID.uuidString).m4a"))
  let plist: [String: Any] = [
    "type": "Farrago.FGTileSet", "title": "Show", "mode": 1, "playbackMode": 2,
    "crossfadeDuration": 0.5, "security": ["locked": true],
    "tiles": [
      [
        "fileUUID": fileID.uuidString, "fileName": "Dog Bark.wav", "title": "Dog Bark",
        "tileIcon": ["🐕", "🦺"], "colorIndex": 3, "gridPositionX": 2, "gridPositionY": 1,
        "listPositionY": 4, "playbackEnabled": false, "holdToPlay": true,
        "lastPlayStart": -62_135_769_600.0,
        "playerSettings": [
          "loop": true, "fadeInTime": 1.5, "fullVolume": 0.8, "duckVolume": 0.3,
          "ducked": true, "startPackets": 10, "endPackets": 0,
        ],
      ],
      ["fileUUID": UUID().uuidString, "title": "Missing"],
    ],
  ]
  try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    .write(to: package.appending(path: "Sound Set Data.plist"))

  let imported = try FarragoImport.read(package: package) { packets, _ in Double(packets) / 100 }

  #expect(imported.set.title == "Show")
  #expect(imported.set.displayMode == .list)
  #expect(imported.set.playbackMode == .continuous)
  #expect(imported.set.crossfadeDuration == 0.5)
  #expect(imported.set.isLocked)
  #expect(imported.skippedTileTitles == ["Missing"])
  let tile = try #require(imported.set.tiles.first)
  #expect(tile.originalFileName == "Dog Bark.m4a")
  #expect(tile.icon == "🐕🦺")
  #expect(tile.color == .orange)
  #expect(tile.gridPosition == GridPosition(column: 2, row: 1))
  #expect(tile.listIndex == 4)
  #expect(!tile.isEnabled && tile.holdToPlay)
  #expect(tile.lastPlayed == nil)
  #expect(tile.player.loops && tile.player.usesVolumeB)
  #expect(tile.player.volumeA == 0.8 && tile.player.volumeB == 0.3)
  #expect(tile.player.fadeInTime == 1.5)
  #expect(tile.player.trimStart == 0.1 && tile.player.trimEnd == 0)

  let store = SetStore(directory: temporaryDirectory("Library"))
  let added = try store.add(imported)
  #expect(try Data(contentsOf: store.soundURL(for: tile, in: added.id)) == Data("dog".utf8))
}

@Test func otherPlistsAreNotFarragoSets() throws {
  let package = temporaryDirectory("Farrago").appending(path: "Other.farragoset")
  try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
  try PropertyListSerialization.data(
    fromPropertyList: ["type": "Other"], format: .binary, options: 0
  )
  .write(to: package.appending(path: "Sound Set Data.plist"))

  #expect(throws: FarragoImportError.notASoundSet("Other.farragoset")) {
    try FarragoImport.read(package: package) { _, _ in 0 }
  }
}

@Test func packagesWithSymbolicLinksAreRefused() throws {
  let package = temporaryDirectory("Export").appending(path: "Trap.soundset")
  let set = SoundSet(title: "Trap")
  try FileManager.default.createDirectory(
    at: package.appending(path: "Sounds"),
    withIntermediateDirectories: true
  )
  try PropertyListEncoder().encode(set).write(to: package.appending(path: "Set.plist"))
  let secret = temporaryDirectory("Secret").appending(path: "secret.txt")
  try writeSound("secret", to: secret)
  try FileManager.default.createSymbolicLink(
    at: package.appending(path: "Sounds/\(UUID().uuidString).m4a"),
    withDestinationURL: secret
  )
  let store = SetStore(directory: temporaryDirectory("Library"))

  #expect(throws: SetStoreError.self) { try store.importPackage(at: package) }
}

@Test func farragoSoundsThatAreSymbolicLinksCountAsMissing() throws {
  let package = temporaryDirectory("Farrago").appending(path: "Trap.farragoset")
  let fileID = UUID()
  let secret = temporaryDirectory("Secret").appending(path: "secret.txt")
  try writeSound("secret", to: secret)
  try FileManager.default.createDirectory(
    at: package.appending(path: "Sound Files"),
    withIntermediateDirectories: true
  )
  try FileManager.default.createSymbolicLink(
    at: package.appending(path: "Sound Files/\(fileID.uuidString).m4a"),
    withDestinationURL: secret
  )
  let plist: [String: Any] = [
    "type": "Farrago.FGTileSet", "title": "Trap",
    "tiles": [["fileUUID": fileID.uuidString, "title": "Secret"]],
  ]
  try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    .write(to: package.appending(path: "Sound Set Data.plist"))

  let imported = try FarragoImport.read(package: package) { _, _ in 0 }

  #expect(imported.set.tiles.isEmpty)
  #expect(imported.skippedTileTitles == ["Secret"])
}

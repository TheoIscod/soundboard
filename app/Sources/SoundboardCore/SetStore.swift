import Foundation

/// The sound set library on disk: one `<set id>.soundset` package per set, holding
/// `Set.plist` and a `Sounds/` folder with a private copy of every audio file.
public struct SetStore: Sendable {
  public static let packageExtension = "soundset"

  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// `~/Library/Application Support/Soundboard/Sets`.
  public static func defaultDirectory() throws -> URL {
    try FileManager.default
      .url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      .appending(path: "Soundboard/Sets", directoryHint: .isDirectory)
  }

  public func loadAll() throws -> [SoundSet] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let packages = try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == Self.packageExtension }
    return try packages.map { try load(from: $0) }.sorted { $0.title < $1.title }
  }

  public func save(_ set: SoundSet) throws {
    let package = packageURL(for: set.id)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(set).write(to: package.appending(path: "Set.plist"), options: .atomic)
  }

  /// Copies the set's package (plist and sounds) to `destination`, replacing what is there.
  public func export(_ set: SoundSet, to destination: URL) throws {
    try save(set)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: packageURL(for: set.id), to: destination)
  }

  /// The id of the set a `.soundset` package holds, without adding it to the library.
  public func setID(ofPackage package: URL) throws -> UUID {
    try load(from: package).id
  }

  /// Adds a copy of an exported `.soundset` package to the library, with fresh identifiers
  /// so importing the same package twice gives two independent sets.
  public func importPackage(at source: URL) throws -> SoundSet {
    let original = try load(from: source)
    let set = original.withFreshIdentifiers()
    let sounds = source.appending(path: "Sounds", directoryHint: .isDirectory)
    let package = packageURL(for: set.id)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: sounds.path) {
      try FileManager.default.copyItem(
        at: sounds,
        to: package.appending(path: "Sounds", directoryHint: .isDirectory)
      )
    }
    try save(set)
    return set
  }

  /// Deletes the set's package, including its copied sounds.
  public func delete(_ setID: UUID) throws {
    let package = packageURL(for: setID)
    guard FileManager.default.fileExists(atPath: package.path) else { return }
    try FileManager.default.removeItem(at: package)
  }

  /// Copies an audio file into the set's package so the set no longer depends on the original.
  public func importSound(from source: URL, for tile: Tile, in setID: UUID) throws {
    let destination = soundURL(for: tile, in: setID)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: source, to: destination)
  }

  /// Deletes the copy of a tile's sound; a copy that is already gone is not an error.
  public func removeSound(for tile: Tile, in setID: UUID) throws {
    let url = soundURL(for: tile, in: setID)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  public func soundURL(for tile: Tile, in setID: UUID) -> URL {
    let fileExtension = (tile.originalFileName as NSString).pathExtension
    let name =
      fileExtension.isEmpty
      ? tile.fileID.uuidString : "\(tile.fileID.uuidString).\(fileExtension)"
    return packageURL(for: setID).appending(path: "Sounds/\(name)")
  }

  private func packageURL(for setID: UUID) -> URL {
    directory.appending(
      path: "\(setID.uuidString).\(Self.packageExtension)",
      directoryHint: .isDirectory
    )
  }

  private func load(from package: URL) throws -> SoundSet {
    let data = try Data(contentsOf: package.appending(path: "Set.plist"))
    let set = try PropertyListDecoder().decode(SoundSet.self, from: data)
    guard set.formatVersion <= SoundSet.formatVersion else {
      throw SetStoreError.newerFormat(set.title, version: set.formatVersion)
    }
    return set
  }
}

public enum SetStoreError: LocalizedError, Equatable {
  case newerFormat(String, version: Int)

  public var errorDescription: String? {
    switch self {
    case .newerFormat(let title, let version):
      "“\(title)” was saved by a newer version of Soundboard (format \(version))."
    }
  }
}

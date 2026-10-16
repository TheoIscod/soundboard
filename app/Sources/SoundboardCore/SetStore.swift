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

  /// Every readable set; an unreadable package (damaged, newer format…) is reported and
  /// skipped so it can't hide the others. Throws only if the library folder can't be listed.
  public func loadAll() throws -> LibraryContents {
    guard FileManager.default.fileExists(atPath: directory.path) else {
      return LibraryContents(sets: [], unreadable: [])
    }
    let packages = try FileManager.default
      .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == Self.packageExtension }
    var contents = LibraryContents(sets: [], unreadable: [])
    for package in packages {
      do {
        contents.sets.append(try load(from: package))
      } catch {
        contents.unreadable.append("\(package.lastPathComponent) : \(error.localizedDescription)")
      }
    }
    return contents
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
    let package = packageURL(for: set.id)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    // Waveforms only depend on the sounds, which keep their ids, so they come along.
    for folder in ["Sounds", "Waveforms"] {
      let source = source.appending(path: folder, directoryHint: .isDirectory)
      guard FileManager.default.fileExists(atPath: source.path) else { continue }
      try Self.refuseSymbolicLinks(in: source)
      try FileManager.default.copyItem(
        at: source,
        to: package.appending(path: folder, directoryHint: .isDirectory)
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
    // Copy the real file behind an alias or symbolic link, not the link itself.
    try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
  }

  /// Deletes the copy of a tile's sound; a copy that is already gone is not an error.
  public func removeSound(for tile: Tile, in setID: UUID) throws {
    let url = soundURL(for: tile, in: setID)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    try removeWaveforms(for: tile, in: setID)
  }

  /// Peaks saved for the tile's sound at this resolution, or nil if there are none (or they
  /// can't be read): the sound file never changes, so its id is enough to find them.
  public func savedWaveform(for tile: Tile, in setID: UUID, binCount: Int) -> [WaveformPeak]? {
    guard let data = try? Data(contentsOf: waveformURL(for: tile, in: setID, binCount: binCount))
    else { return nil }
    return WaveformFile.decode(data)
  }

  public func saveWaveform(
    _ peaks: [WaveformPeak],
    for tile: Tile,
    in setID: UUID,
    binCount: Int
  ) throws {
    let url = waveformURL(for: tile, in: setID, binCount: binCount)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try WaveformFile.encode(peaks).write(to: url, options: .atomic)
  }

  private func removeWaveforms(for tile: Tile, in setID: UUID) throws {
    let folder = packageURL(for: setID).appending(path: "Waveforms", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path) else { return }
    for file in try FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil
    ) where file.lastPathComponent.hasPrefix(tile.fileID.uuidString) {
      try FileManager.default.removeItem(at: file)
    }
  }

  private func waveformURL(for tile: Tile, in setID: UUID, binCount: Int) -> URL {
    packageURL(for: setID)
      .appending(path: "Waveforms/\(tile.fileID.uuidString)-\(binCount).peaks")
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

extension SetStore {
  /// An imported package must only hold real files: a symbolic link could make the import
  /// copy any file of the Mac into the library (and into later exports).
  static func refuseSymbolicLinks(in folder: URL) throws {
    let items = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: [.isSymbolicLinkKey]
    )
    while let item = items?.nextObject() as? URL {
      if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
        throw SetStoreError.symbolicLink(item.lastPathComponent)
      }
    }
  }
}

public struct LibraryContents: Sendable {
  public var sets: [SoundSet]
  /// One line per package that couldn't be read: its name and why.
  public var unreadable: [String]
}

public enum SetStoreError: LocalizedError, Equatable {
  case newerFormat(String, version: Int)
  case symbolicLink(String)

  public var errorDescription: String? {
    switch self {
    case .newerFormat(let title, let version):
      "« \(title) » a été enregistré par une version plus récente de Soundboard (format \(version))."
    case .symbolicLink(let name):
      "Le set contient un lien symbolique (« \(name) ») : il n’est pas importé par sécurité."
    }
  }
}

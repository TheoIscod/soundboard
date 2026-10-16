import Foundation

/// A Farrago `.farragoset` package read into our model, before its sounds are copied.
/// Field meanings come from analysis/notes/01-sound-set-format.md.
public struct FarragoImport: Sendable {
  public var set: SoundSet
  /// Where each tile's sound is inside the Farrago package, by sound file id.
  public var soundFiles: [UUID: URL]
  /// Tiles left out because their sound file is missing from the package.
  public var skippedTileTitles: [String]

  /// Converts Farrago's trim, counted in codec packets, to seconds for one sound file.
  public typealias PacketDuration = (_ packets: Int, _ soundFile: URL) throws -> TimeInterval

  public static func read(package: URL, packetDuration: PacketDuration) throws -> FarragoImport {
    let data = try Data(contentsOf: package.appending(path: "Sound Set Data.plist"))
    guard
      let root = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      root["type"] as? String == "Farrago.FGTileSet"
    else { throw FarragoImportError.notASoundSet(package.lastPathComponent) }

    var set = SoundSet(
      title: root["title"] as? String ?? package.deletingPathExtension().lastPathComponent
    )
    set.notes = root["notes"] as? String ?? ""
    set.displayMode = root["mode"] as? Int == 1 ? .list : .grid
    set.playbackMode = (root["playbackMode"] as? Int).flatMap(PlaybackMode.init) ?? .toggle
    set.crossfadeDuration = root["crossfadeDuration"] as? Double ?? 0
    set.isLocked = (root["security"] as? [String: Any])?["locked"] as? Bool ?? false

    let soundsFolder = package.appending(path: "Sound Files", directoryHint: .isDirectory)
    // A package without its sound folder still imports; every tile is then reported skipped.
    let available =
      (try? FileManager.default.contentsOfDirectory(
        at: soundsFolder, includingPropertiesForKeys: nil))
      ?? []
    var soundFiles: [UUID: URL] = [:]
    var skipped: [String] = []

    for case let entry as [String: Any] in root["tiles"] as? [Any] ?? [] {
      let title = entry["title"] as? String ?? "Untitled"
      guard let fileID = (entry["fileUUID"] as? String).flatMap(UUID.init(uuidString:)),
        let source = available.first(where: {
          $0.deletingPathExtension().lastPathComponent == fileID.uuidString
        })
      else {
        skipped.append(title)
        continue
      }
      set.tiles.append(
        try tile(from: entry, title: title, fileID: fileID, source: source, packetDuration)
      )
      soundFiles[fileID] = source
    }
    return FarragoImport(set: set, soundFiles: soundFiles, skippedTileTitles: skipped)
  }

  private static func tile(
    from entry: [String: Any],
    title: String,
    fileID: UUID,
    source: URL,
    _ packetDuration: PacketDuration
  ) throws -> Tile {
    // Our package names sounds after the original file's extension, so it must match the copy.
    let baseName = ((entry["fileName"] as? String ?? title) as NSString).deletingPathExtension
    var tile = Tile(
      fileID: fileID,
      originalFileName: "\(baseName).\(source.pathExtension)",
      title: title
    )
    tile.icon = (entry["tileIcon"] as? [String])?.joined() ?? ""
    tile.notes = entry["notes"] as? String ?? ""
    // Farrago's colour order is not confirmed; the Shortcuts enum order is assumed.
    tile.color = (entry["colorIndex"] as? Int).flatMap(TileColor.init) ?? .purple
    tile.gridPosition = GridPosition(
      column: entry["gridPositionX"] as? Int ?? 0,
      row: entry["gridPositionY"] as? Int ?? 0
    )
    tile.listIndex = entry["listPositionY"] as? Int ?? 0
    tile.isEnabled = entry["playbackEnabled"] as? Bool ?? true
    tile.isFavorite = entry["favorite"] as? Bool ?? false
    tile.holdToPlay = entry["holdToPlay"] as? Bool ?? false
    tile.solo = entry["solo"] as? Bool ?? false
    // Never-played tiles carry a year-1 sentinel, i.e. a negative Unix time.
    if let lastPlay = entry["lastPlayStart"] as? Double, lastPlay > 0 {
      tile.lastPlayed = Date(timeIntervalSince1970: lastPlay)
    }

    let player = entry["playerSettings"] as? [String: Any] ?? [:]
    tile.player.loops = player["loop"] as? Bool ?? false
    tile.player.fadeInTime = player["fadeInTime"] as? Double ?? 0
    tile.player.fadeOutTime = player["fadeOutTime"] as? Double ?? 0
    tile.player.volumeA = Float(player["fullVolume"] as? Double ?? 1)
    tile.player.volumeB = Float(player["duckVolume"] as? Double ?? 0.4)
    tile.player.usesVolumeB = player["ducked"] as? Bool ?? false
    tile.player.muted = player["muted"] as? Bool ?? false
    tile.player.pausable = player["defaultToPause"] as? Bool ?? false
    if let start = player["startPackets"] as? Int, start > 0 {
      tile.player.trimStart = try packetDuration(start, source)
    }
    if let end = player["endPackets"] as? Int, end > 0 {
      tile.player.trimEnd = try packetDuration(end, source)
    }
    return tile
  }
}

public enum FarragoImportError: LocalizedError, Equatable {
  case notASoundSet(String)

  public var errorDescription: String? {
    switch self {
    case .notASoundSet(let name): "“\(name)” isn’t a Farrago sound set."
    }
  }
}

extension SetStore {
  /// Adds a read Farrago set to the library, copying its sounds into a new package.
  public func add(_ imported: FarragoImport) throws -> SoundSet {
    for tile in imported.set.tiles {
      guard let source = imported.soundFiles[tile.fileID] else { continue }
      try importSound(from: source, for: tile, in: imported.set.id)
    }
    try save(imported.set)
    return imported.set
  }
}

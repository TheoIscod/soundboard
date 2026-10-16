import AVFoundation
import AppKit
import SoundboardCore

enum SetFiles {
  /// Packages the app opens as sets rather than as sounds.
  static func isSetPackage(_ url: URL) -> Bool {
    [SetStore.packageExtension, "farragoset"].contains(url.pathExtension.lowercased())
  }

  /// Length of `packets` codec packets of a sound file, for Farrago's packet-based trim
  /// (AAC packets hold 1024 frames, MP3 1152, PCM 1).
  static func seconds(ofPackets packets: Int, in url: URL) throws -> TimeInterval {
    let format = try AVAudioFile(forReading: url).fileFormat
    let framesPerPacket = format.streamDescription.pointee.mFramesPerPacket
    return Double(packets) * Double(max(framesPerPacket, 1)) / format.sampleRate
  }

  @MainActor
  static func chooseExportDestination(for set: SoundSet) -> URL? {
    let panel = NSSavePanel()
    panel.title = "Export Set"
    panel.nameFieldStringValue = "\(set.title).\(SetStore.packageExtension)"
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
  }

  @MainActor
  static func chooseSetsToImport() -> [URL] {
    let panel = NSOpenPanel()
    panel.title = "Import Sets"
    panel.message = "Choose sets exported by Soundboard (.soundset) or Farrago sets (.farragoset)."
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    return panel.runModal() == .OK ? panel.urls : []
  }
}

import AVFoundation
import SoundboardCore

enum WaveformLoader {
  /// Slices drawn across the editor, whatever the sound's length.
  static let binCount = 600

  /// Reads the whole file, mixes its channels to mono and reduces it to peaks.
  /// Blocking: call it off the main actor.
  static func peaks(of url: URL) throws -> [WaveformPeak] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard file.length > 0,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(file.length)
      )
    else { return [] }
    try file.read(into: buffer)
    guard let channels = buffer.floatChannelData else { return [] }

    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(format.channelCount)
    var mono = [Float](repeating: 0, count: frameCount)
    for channel in 0..<channelCount {
      let samples = channels[channel]
      for frame in 0..<frameCount { mono[frame] += samples[frame] }
    }
    if channelCount > 1 {
      let scale = 1 / Float(channelCount)
      for frame in 0..<frameCount { mono[frame] *= scale }
    }
    return Waveform.peaks(of: mono, binCount: binCount)
  }
}

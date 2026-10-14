import AVFoundation
import SoundboardCore

/// Plays tiles: one player node per sounding tile, mixed by AVAudioEngine.
/// Gains are recomputed on a 60 Hz timer from the ramps and envelope in SoundboardCore.
@MainActor
final class AudioEngine {
  var onVoiceFinished: ((UUID) -> Void)?

  private let engine = AVAudioEngine()
  private var voices: [UUID: Voice] = [:]
  private var buffers: [BufferKey: AVAudioPCMBuffer] = [:]
  private var timer: Timer?
  private var lastTick = ProcessInfo.processInfo.systemUptime

  func start(_ tile: Tile, url: URL) throws {
    if voices[tile.id] != nil { removeVoice(tile.id) }

    let buffer = try trimmedBuffer(for: tile, url: url)
    let voice = Voice(
      settings: tile.player,
      length: Double(buffer.frameLength) / buffer.format.sampleRate
    )
    engine.attach(voice.player)
    engine.connect(voice.player, to: engine.mainMixerNode, format: buffer.format)
    if !engine.isRunning { try engine.start() }

    voice.player.scheduleBuffer(
      buffer,
      at: nil,
      options: tile.player.loops ? .loops : [],
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      Task { @MainActor in self?.voiceReachedEnd(tile.id, voice: voice) }
    }
    voice.player.volume = voice.gain
    voice.player.play()
    voices[tile.id] = voice
    startTimerIfNeeded()
  }

  /// `fade == nil` cuts immediately; otherwise fades to silence, then stops.
  func stop(_ tileID: UUID, fade: TimeInterval?) {
    guard let voice = voices[tileID] else { return }
    guard let fade, fade > 0 else {
      removeVoice(tileID)
      return
    }
    voice.fade.move(to: 0, over: fade)
    voice.stopsWhenSilent = true
  }

  func pause(_ tileID: UUID) {
    voices[tileID]?.player.pause()
  }

  func resume(_ tileID: UUID) {
    voices[tileID]?.player.play()
  }

  private func trimmedBuffer(for tile: Tile, url: URL) throws -> AVAudioPCMBuffer {
    let key = BufferKey(
      fileID: tile.fileID,
      trimStart: tile.player.trimStart,
      trimEnd: tile.player.trimEnd
    )
    if let cached = buffers[key] { return cached }

    let file = try AVAudioFile(forReading: url)
    let sampleRate = file.processingFormat.sampleRate
    let startFrame = AVAudioFramePosition(tile.player.trimStart * sampleRate)
    let endFrame = file.length - AVAudioFramePosition(tile.player.trimEnd * sampleRate)
    let frameCount = AVAudioFrameCount(max(endFrame - startFrame, 0))
    guard frameCount > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
    else { throw AudioEngineError.emptyRegion(tile.title) }

    file.framePosition = startFrame
    try file.read(into: buffer, frameCount: frameCount)
    buffers[key] = buffer
    return buffer
  }

  private func voiceReachedEnd(_ tileID: UUID, voice: Voice) {
    // Stopping a node also fires its completion; ignore voices already replaced or removed.
    guard voices[tileID] === voice else { return }
    removeVoice(tileID)
    onVoiceFinished?(tileID)
  }

  private func removeVoice(_ tileID: UUID) {
    guard let voice = voices.removeValue(forKey: tileID) else { return }
    voice.player.stop()
    engine.detach(voice.player)
    if voices.isEmpty {
      timer?.invalidate()
      timer = nil
    }
  }

  private func startTimerIfNeeded() {
    guard timer == nil else { return }
    lastTick = ProcessInfo.processInfo.systemUptime
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  private func tick() {
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = now - lastTick
    lastTick = now

    for (tileID, voice) in voices {
      voice.fade.advance(by: elapsed)
      if voice.stopsWhenSilent, voice.fade.isFinished {
        removeVoice(tileID)
        onVoiceFinished?(tileID)
        continue
      }
      voice.position = currentPosition(of: voice)
      voice.player.volume = voice.gain
    }
  }

  private func currentPosition(of voice: Voice) -> TimeInterval {
    guard let nodeTime = voice.player.lastRenderTime,
      let playerTime = voice.player.playerTime(forNodeTime: nodeTime),
      voice.length > 0
    else { return voice.position }
    let seconds = Double(playerTime.sampleTime) / playerTime.sampleRate
    return voice.settings.loops ? seconds.truncatingRemainder(dividingBy: voice.length) : seconds
  }
}

enum AudioEngineError: LocalizedError {
  case emptyRegion(String)

  var errorDescription: String? {
    switch self {
    case .emptyRegion(let title): "“\(title)” has nothing left to play after trimming."
    }
  }
}

private struct BufferKey: Hashable {
  let fileID: UUID
  let trimStart: TimeInterval
  let trimEnd: TimeInterval
}

@MainActor
private final class Voice {
  let player = AVAudioPlayerNode()
  let settings: PlayerSettings
  let length: TimeInterval
  var fade = LinearRamp(value: 1)
  var stopsWhenSilent = false
  var position: TimeInterval = 0

  init(settings: PlayerSettings, length: TimeInterval) {
    self.settings = settings
    self.length = length
  }

  var gain: Float {
    let volume = settings.muted ? 0 : settings.activeVolume
    let envelope = Gain.envelope(
      at: position,
      length: length,
      fadeIn: settings.fadeInTime,
      fadeOut: settings.fadeOutTime
    )
    return Gain.snapped(volume * fade.value * envelope)
  }
}

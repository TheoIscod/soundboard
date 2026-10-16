import AVFoundation
import SoundboardCore

/// Plays tiles: one player node per sounding tile, mixed by AVAudioEngine.
/// Gains are recomputed on a 60 Hz timer from the ramps and envelope in SoundboardCore.
@MainActor
final class AudioEngine {
  var onVoiceFinished: ((UUID) -> Void)?
  /// Continuous mode: the voice reached the point where the next tile should start,
  /// `lead` seconds before its end (0 = at the end). Fires at most once per voice.
  var onAdvancePoint: ((UUID, _ lead: TimeInterval) -> Void)?

  private let engine = AVAudioEngine()
  private var voices: [UUID: Voice] = [:]
  private var buffers: [BufferKey: AVAudioPCMBuffer] = [:]
  private var timer: Timer?
  private var lastTick = ProcessInfo.processInfo.systemUptime
  private var master = LinearRamp(value: 1)
  private var configurationObserver: (any NSObjectProtocol)?

  init() {
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.outputDidChange() }
    }
  }

  /// The output device or its format changed (headphones plugged in, Bluetooth connected…).
  /// AVAudioEngine has stopped and dropped what was scheduled, so the sounds that were
  /// playing are reported as ended, and the mixer is reconnected to the new output format;
  /// the engine restarts with the next sound.
  private func outputDidChange() {
    for tileID in Array(voices.keys) {
      removeVoice(tileID)
      onVoiceFinished?(tileID)
    }
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
  }

  /// Ramps every sound to the new master gain over 0.2 s.
  func setMasterGain(_ gain: Float) {
    // With nothing sounding there is nothing to ramp, and the timer that advances ramps is off.
    master.move(to: gain, over: voices.isEmpty ? 0 : LinearRamp.volumeChangeDuration)
  }

  /// - Parameters:
  ///   - fadeIn: > 0 starts from silence and ramps up over this time.
  ///   - continuousCrossfade: the set's crossfade when Continuous is active, to report
  ///     the advance point through `onAdvancePoint`; nil when the set doesn't advance.
  func start(
    _ tile: Tile,
    url: URL,
    fadeIn: TimeInterval = 0,
    velocity: Float = 1,
    continuousCrossfade: TimeInterval? = nil
  ) throws {
    if voices[tile.id] != nil { removeVoice(tile.id) }

    let buffer = try trimmedBuffer(for: tile, url: url)
    let length = Double(buffer.frameLength) / buffer.format.sampleRate
    let voice = Voice(settings: tile.player, buffer: buffer)
    voice.velocity = velocity
    if fadeIn > 0 {
      voice.fade = LinearRamp(value: 0)
      voice.fade.move(to: 1, over: fadeIn)
    }
    voice.advanceLead = continuousCrossfade.map {
      SoundSet.crossfadeLead(crossfade: $0, soundLength: length)
    }
    engine.attach(voice.player)
    engine.connect(voice.player, to: engine.mainMixerNode, format: buffer.format)
    if !engine.isRunning { try engine.start() }

    schedule(voice, for: tile.id, from: 0)
    voice.player.volume = Gain.snapped(master.value * voice.gain)
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

  /// Applies edited settings to a sounding tile; volume changes ramp over 0.2 s.
  func update(_ tile: Tile) {
    voices[tile.id]?.settings = tile.player
  }

  /// Seconds played since the tile's trimmed start, while it sounds.
  func position(of tileID: UUID) -> TimeInterval? {
    voices[tileID]?.position
  }

  /// Length of the whole file, before trimming.
  func duration(of url: URL) throws -> TimeInterval {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.processingFormat.sampleRate
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

  /// Moves a sounding tile's playback to `position` seconds into its trimmed region; a paused
  /// tile resumes from there.
  func seek(_ tileID: UUID, to position: TimeInterval) {
    guard let voice = voices[tileID] else { return }
    let target = Seek.target(position, length: voice.length, loops: voice.loops)
    let wasPlaying = voice.player.isPlaying
    voice.player.stop()
    schedule(voice, for: tileID, from: target)
    if target < voice.length - (voice.advanceLead ?? 0) { voice.hasAdvanced = false }
    voice.position = target
    if wasPlaying { voice.player.play() }
  }

  /// Seconds into the trimmed region where a sounding tile is, and the region's length.
  func playback(of tileID: UUID) -> (position: TimeInterval, length: TimeInterval)? {
    voices[tileID].map { ($0.position, $0.length) }
  }

  /// Schedules the voice's sound from `start` seconds: the rest of the region, then for
  /// looping sounds the whole region again and again.
  private func schedule(_ voice: Voice, for tileID: UUID, from start: TimeInterval) {
    voice.schedule += 1
    let schedule = voice.schedule
    voice.offset = start
    let frame = AVAudioFrameCount(max(start, 0) * voice.buffer.format.sampleRate)
    // Explicitly @Sendable: called on an audio thread, so it must not be main-actor isolated.
    let completion: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = {
      [weak self] _ in
      Task { @MainActor in self?.voiceReachedEnd(tileID, voice: voice, schedule: schedule) }
    }
    if frame == 0 {
      voice.player.scheduleBuffer(
        voice.buffer,
        at: nil,
        options: voice.loops ? .loops : [],
        completionCallbackType: .dataPlayedBack,
        completionHandler: completion
      )
      return
    }
    let rest = Self.slice(of: voice.buffer, from: frame)
    if voice.loops {
      voice.player.scheduleBuffer(rest, completionHandler: nil)
      voice.player.scheduleBuffer(
        voice.buffer,
        at: nil,
        options: .loops,
        completionCallbackType: .dataPlayedBack,
        completionHandler: completion
      )
    } else {
      voice.player.scheduleBuffer(
        rest,
        at: nil,
        options: [],
        completionCallbackType: .dataPlayedBack,
        completionHandler: completion
      )
    }
  }

  /// The frames of `buffer` from `frame` to its end, as a new buffer.
  private static func slice(of buffer: AVAudioPCMBuffer, from frame: AVAudioFrameCount)
    -> AVAudioPCMBuffer
  {
    let count = buffer.frameLength - min(frame, buffer.frameLength)
    guard count > 0,
      let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
      let source = buffer.floatChannelData, let target = slice.floatChannelData
    else { return buffer }
    for channel in 0..<Int(buffer.format.channelCount) {
      target[channel].update(from: source[channel] + Int(frame), count: Int(count))
    }
    slice.frameLength = count
    return slice
  }

  private func voiceReachedEnd(_ tileID: UUID, voice: Voice, schedule: Int) {
    // Stopping a node also fires its completion, as does seeking (which reschedules);
    // ignore voices replaced or removed, and schedules a seek has replaced.
    guard voices[tileID] === voice, voice.schedule == schedule else { return }
    // The timer may not have seen the last moments of the sound: advance before finishing.
    reportAdvanceIfNeeded(tileID, voice: voice, force: true)
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
    master.advance(by: elapsed)

    for (tileID, voice) in voices {
      voice.volume.advance(by: elapsed)
      voice.fade.advance(by: elapsed)
      if voice.stopsWhenSilent, voice.fade.isFinished {
        removeVoice(tileID)
        onVoiceFinished?(tileID)
        continue
      }
      voice.position = currentPosition(of: voice)
      reportAdvanceIfNeeded(tileID, voice: voice, force: false)
      voice.player.volume = Gain.snapped(master.value * voice.gain)
    }
  }

  /// A voice already fading out (stopped by the user or by a crossfade) never advances.
  private func reportAdvanceIfNeeded(_ tileID: UUID, voice: Voice, force: Bool) {
    guard let lead = voice.advanceLead, !voice.hasAdvanced, !voice.stopsWhenSilent else { return }
    guard force || voice.position >= voice.length - lead else { return }
    voice.hasAdvanced = true
    onAdvancePoint?(tileID, lead)
  }

  private func currentPosition(of voice: Voice) -> TimeInterval {
    guard let nodeTime = voice.player.lastRenderTime,
      let playerTime = voice.player.playerTime(forNodeTime: nodeTime),
      voice.length > 0
    else { return voice.position }
    // Player time restarts at 0 whenever a seek reschedules, from `offset`.
    let seconds = voice.offset + Double(playerTime.sampleTime) / playerTime.sampleRate
    return voice.loops ? seconds.truncatingRemainder(dividingBy: voice.length) : seconds
  }
}

enum AudioEngineError: LocalizedError {
  case emptyRegion(String)

  var errorDescription: String? {
    switch self {
    case .emptyRegion(let title): "« \(title) » est vide une fois découpé."
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
  /// Fades and volume follow edits live; trim and loop are fixed by the scheduled buffer.
  var settings: PlayerSettings {
    didSet { volume.move(to: Self.volume(for: settings), over: LinearRamp.volumeChangeDuration) }
  }
  let loops: Bool
  /// The trimmed region, kept to reschedule it when seeking.
  let buffer: AVAudioPCMBuffer
  let length: TimeInterval
  /// Where the current schedule started, in seconds into the region.
  var offset: TimeInterval = 0
  /// Bumped on every (re)schedule, so completions of replaced schedules are ignored.
  var schedule = 0
  var volume: LinearRamp
  var fade = LinearRamp(value: 1)
  /// MIDI velocity as a gain factor, 1 for mouse and keyboard triggers.
  var velocity: Float = 1
  var stopsWhenSilent = false
  var position: TimeInterval = 0
  /// Seconds before the end at which Continuous starts the next tile; nil if it doesn't.
  var advanceLead: TimeInterval?
  var hasAdvanced = false

  init(settings: PlayerSettings, buffer: AVAudioPCMBuffer) {
    self.settings = settings
    self.buffer = buffer
    length = Double(buffer.frameLength) / buffer.format.sampleRate
    loops = settings.loops
    volume = LinearRamp(value: Self.volume(for: settings))
  }

  private static func volume(for settings: PlayerSettings) -> Float {
    settings.muted ? 0 : settings.activeVolume
  }

  var gain: Float {
    let envelope = Gain.envelope(
      at: position,
      length: length,
      fadeIn: settings.fadeInTime,
      fadeOut: settings.fadeOutTime
    )
    return Gain.snapped(volume.value * velocity * fade.value * envelope)
  }
}

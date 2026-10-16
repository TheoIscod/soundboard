import CoreMIDI
import Foundation
import Observation
import SoundboardCore
import os

/// Lights a controller's pads while their tiles play, by sending note-on / note-off to one
/// MIDI destination chosen in Settings. Only changes are sent (see `MIDILights`).
@MainActor
@Observable
final class MIDIOutput {
  struct Destination: Identifiable, Hashable {
    /// CoreMIDI's unique id, stable across launches for a given device.
    let id: MIDIUniqueID
    let name: String
  }

  private static let destinationKey = "midiOutputDestination"
  private static let velocityKey = "midiOutputVelocity"
  private nonisolated static let log = Logger(
    subsystem: "io.github.theoiscod.soundboard",
    category: "midi-out"
  )

  private(set) var destinations: [Destination] = []
  /// Nil sends nothing.
  var destinationID: MIDIUniqueID? {
    didSet { settingsChanged(previousDestination: oldValue) }
  }
  /// Velocity of lit pads, 1…127; many pad controllers read it as a colour.
  var velocity: Int {
    didSet { settingsChanged(previousDestination: destinationID) }
  }

  @ObservationIgnored private var client = MIDIClientRef()
  @ObservationIgnored private var port = MIDIPortRef()
  @ObservationIgnored private var lights = MIDILights()
  @ObservationIgnored private var wanted: Set<MIDINote> = []

  init() {
    let defaults = UserDefaults.standard
    destinationID = defaults.object(forKey: Self.destinationKey) as? MIDIUniqueID
    velocity = defaults.object(forKey: Self.velocityKey) as? Int ?? 127
    do {
      client = try Self.makeClient { [weak self] in self?.refreshDestinations() }
      var port = MIDIPortRef()
      let status = MIDIOutputPortCreate(client, "Soundboard" as CFString, &port)
      guard status == noErr else { throw MIDIInputError.couldNotStart(status) }
      self.port = port
    } catch {
      Self.log.error("MIDI output unavailable: \(error.localizedDescription, privacy: .public)")
    }
    refreshDestinations()
  }

  /// Lights exactly these notes on the chosen controller.
  func show(_ notes: Set<MIDINote>) {
    wanted = notes
    send(lights.update(to: notes, velocity: velocity), to: destinationID)
  }

  func refreshDestinations() {
    destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { index in
      let endpoint = MIDIGetDestination(index)
      guard endpoint != 0 else { return nil }
      var id: MIDIUniqueID = 0
      var name: Unmanaged<CFString>?
      MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
      MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
      return Destination(id: id, name: (name?.takeRetainedValue() as String?) ?? "MIDI \(id)")
    }
  }

  private func settingsChanged(previousDestination: MIDIUniqueID?) {
    let defaults = UserDefaults.standard
    defaults.set(destinationID, forKey: Self.destinationKey)
    defaults.set(velocity, forKey: Self.velocityKey)
    // Turn the old pads off where they were lit, then light the current ones afresh.
    send(lights.update(to: [], velocity: velocity), to: previousDestination)
    show(wanted)
  }

  private func send(_ messages: [MIDIMessage], to destinationID: MIDIUniqueID?) {
    guard !messages.isEmpty, port != 0, let destinationID else { return }
    var object = MIDIObjectRef()
    var type = MIDIObjectType.other
    guard MIDIObjectFindByUniqueID(destinationID, &object, &type) == noErr,
      type == .destination || type == .externalDestination
    else { return }
    for message in messages {
      var list = MIDIEventList()
      let packet = MIDIEventListInit(&list, ._1_0)
      var word = message.universalPacketWord
      _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
      MIDISendEventList(port, object, &list)
      Self.log.debug("MIDI out \(String(describing: message), privacy: .public)")
    }
  }

  /// Built in a nonisolated function so the callback isn't inferred main-actor isolated.
  private nonisolated static func makeClient(
    onSetupChange: @escaping @MainActor @Sendable () -> Void
  ) throws -> MIDIClientRef {
    var client = MIDIClientRef()
    let status = MIDIClientCreateWithBlock("Soundboard output" as CFString, &client) {
      notification in
      guard notification.pointee.messageID == .msgSetupChanged else { return }
      Task { @MainActor in onSetupChange() }
    }
    guard status == noErr else { throw MIDIInputError.couldNotStart(status) }
    return client
  }
}

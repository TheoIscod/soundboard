import CoreMIDI
import SoundboardCore
import os

/// Listens to every MIDI source (controllers, virtual ports) and hands note messages to the
/// board on the main actor. Sources plugged in later are connected when the MIDI setup changes.
@MainActor
final class MIDIInput {
  private nonisolated static let log = Logger(
    subsystem: "io.github.theoiscod.soundboard",
    category: "midi"
  )

  private var client = MIDIClientRef()
  private var port = MIDIPortRef()
  private var connectedSources: Set<MIDIEndpointRef> = []
  private weak var model: BoardModel?

  func install(model: BoardModel) {
    guard client == 0 else { return }
    self.model = model
    do {
      client = try Self.makeClient { [weak self] in self?.connectSources() }
      port = try Self.makeInputPort(client: client) { [weak model] message in
        model?.handleMIDI(message)
      }
      connectSources()
    } catch {
      model.errorMessage = error.localizedDescription
    }
  }

  private func connectSources() {
    let sources = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { $0 != 0 }
    for source in sources where !connectedSources.contains(source) {
      if MIDIPortConnectSource(port, source, nil) == noErr {
        connectedSources.insert(source)
      }
    }
    // Unplugged sources disappear from the list; CoreMIDI has already disconnected them.
    connectedSources.formIntersection(sources)
    model?.midiSourceCount = connectedSources.count
    Self.log.info("Listening to \(self.connectedSources.count) MIDI source(s)")
  }

  // The CoreMIDI callbacks below run on CoreMIDI's threads. They are built in nonisolated
  // functions so Swift doesn't infer main-actor isolation for them (which would trap when
  // CoreMIDI calls them), and they hop to the main actor explicitly.

  private nonisolated static func makeClient(
    onSetupChange: @escaping @MainActor @Sendable () -> Void
  ) throws -> MIDIClientRef {
    var client = MIDIClientRef()
    let status = MIDIClientCreateWithBlock("Soundboard" as CFString, &client) { notification in
      guard notification.pointee.messageID == .msgSetupChanged else { return }
      Task { @MainActor in onSetupChange() }
    }
    guard status == noErr else { throw MIDIInputError.couldNotStart(status) }
    return client
  }

  private nonisolated static func makeInputPort(
    client: MIDIClientRef,
    onMessage: @escaping @MainActor @Sendable (MIDIMessage) -> Void
  ) throws -> MIDIPortRef {
    var port = MIDIPortRef()
    let status = MIDIInputPortCreateWithProtocol(
      client,
      "Soundboard" as CFString,
      ._1_0,
      &port
    ) { eventList, _ in
      var messages: [MIDIMessage] = []
      for packet in eventList.unsafeSequence() {
        for word in packet.words() {
          if let message = MIDIMessage(universalPacketWord: word) { messages.append(message) }
        }
      }
      guard !messages.isEmpty else { return }
      for message in messages { log.debug("MIDI \(String(describing: message), privacy: .public)") }
      // One hop for the whole list keeps the notes in the order they were played.
      Task { @MainActor in messages.forEach(onMessage) }
    }
    guard status == noErr else { throw MIDIInputError.couldNotStart(status) }
    return port
  }
}

enum MIDIInputError: LocalizedError {
  case couldNotStart(OSStatus)

  var errorDescription: String? {
    switch self {
    case .couldNotStart(let status): "Le MIDI n’a pas pu démarrer (erreur \(status))."
    }
  }
}

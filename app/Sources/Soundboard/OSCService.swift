import Foundation
import Network
import Observation
import SoundboardCore
import os

/// Receives OSC over UDP and sends playing-state feedback to a controller. Settings are kept in
/// preferences; reception is off until enabled, so macOS only asks for local network access
/// once it is wanted.
@MainActor
@Observable
final class OSCService {
  static let defaultInputPort = 8080
  static let defaultOutputHost = "127.0.0.1"
  static let defaultOutputPort = 8081

  var inputEnabled: Bool { didSet { settingsChanged() } }
  var inputPort: Int { didSet { settingsChanged() } }
  var outputEnabled: Bool { didSet { settingsChanged() } }
  var outputHost: String { didSet { settingsChanged() } }
  var outputPort: Int { didSet { settingsChanged() } }
  private(set) var inputStatus = "Désactivée"

  @ObservationIgnored var onCommand: ((OSCCommand) -> Void)?
  @ObservationIgnored private var listener: NWListener?
  @ObservationIgnored private var output: NWConnection?
  private nonisolated static let queue = DispatchQueue(label: "io.github.theoiscod.soundboard.osc")
  private nonisolated static let log = Logger(
    subsystem: "io.github.theoiscod.soundboard",
    category: "osc"
  )

  init() {
    let defaults = UserDefaults.standard
    inputEnabled = defaults.bool(forKey: Keys.inputEnabled)
    inputPort = defaults.object(forKey: Keys.inputPort) as? Int ?? Self.defaultInputPort
    outputEnabled = defaults.bool(forKey: Keys.outputEnabled)
    outputHost = defaults.string(forKey: Keys.outputHost) ?? Self.defaultOutputHost
    outputPort = defaults.object(forKey: Keys.outputPort) as? Int ?? Self.defaultOutputPort
    restart()
  }

  func send(_ message: OSCMessage) {
    output?.send(content: message.encoded(), completion: .idempotent)
  }

  private func settingsChanged() {
    let defaults = UserDefaults.standard
    defaults.set(inputEnabled, forKey: Keys.inputEnabled)
    defaults.set(inputPort, forKey: Keys.inputPort)
    defaults.set(outputEnabled, forKey: Keys.outputEnabled)
    defaults.set(outputHost, forKey: Keys.outputHost)
    defaults.set(outputPort, forKey: Keys.outputPort)
    restart()
  }

  private func restart() {
    listener?.cancel()
    listener = nil
    output?.cancel()
    output = nil

    if inputEnabled {
      if let port = NWEndpoint.Port(rawValue: UInt16(clamping: inputPort)), inputPort > 0 {
        do {
          listener = try Self.makeListener(
            port: port,
            onMessages: { [weak self] messages in self?.received(messages) },
            onStatus: { [weak self] status in self?.inputStatus = status }
          )
          inputStatus = "Démarrage…"
        } catch {
          inputStatus = "Erreur : \(error.localizedDescription)"
        }
      } else {
        inputStatus = "Port invalide"
      }
    } else {
      inputStatus = "Désactivée"
    }

    if outputEnabled, !outputHost.isEmpty,
      let port = NWEndpoint.Port(rawValue: UInt16(clamping: outputPort)), outputPort > 0
    {
      let connection = NWConnection(host: NWEndpoint.Host(outputHost), port: port, using: .udp)
      connection.start(queue: Self.queue)
      output = connection
    }
  }

  private func received(_ messages: [OSCMessage]) {
    for message in messages {
      guard let command = OSCCommand(message) else {
        Self.log.debug("OSC ignored \(message.address, privacy: .public)")
        continue
      }
      Self.log.debug("OSC \(String(describing: command), privacy: .public)")
      onCommand?(command)
    }
  }

  // Network calls these on its own queue; they are built in nonisolated functions and hop to
  // the main actor explicitly.

  private nonisolated static func makeListener(
    port: NWEndpoint.Port,
    onMessages: @escaping @MainActor @Sendable ([OSCMessage]) -> Void,
    onStatus: @escaping @MainActor @Sendable (String) -> Void
  ) throws -> NWListener {
    let listener = try NWListener(using: .udp, on: port)
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      receive(on: connection, onMessages: onMessages)
    }
    listener.stateUpdateHandler = { state in
      let status: String
      switch state {
      case .ready: status = "Écoute sur le port \(port)"
      case .waiting(let error): status = "En attente : \(error.localizedDescription)"
      case .failed(let error): status = "Erreur : \(error.localizedDescription)"
      default: return
      }
      Task { @MainActor in onStatus(status) }
    }
    listener.start(queue: queue)
    return listener
  }

  private nonisolated static func receive(
    on connection: NWConnection,
    onMessages: @escaping @MainActor @Sendable ([OSCMessage]) -> Void
  ) {
    connection.receiveMessage { data, _, _, error in
      if let data, !data.isEmpty {
        let messages = OSCMessage.decodePacket(data)
        if !messages.isEmpty { Task { @MainActor in onMessages(messages) } }
      }
      if error == nil {
        receive(on: connection, onMessages: onMessages)
      } else {
        connection.cancel()
      }
    }
  }

  private enum Keys {
    static let inputEnabled = "oscInputEnabled"
    static let inputPort = "oscInputPort"
    static let outputEnabled = "oscOutputEnabled"
    static let outputHost = "oscOutputHost"
    static let outputPort = "oscOutputPort"
  }
}

import Foundation

/// A `soundboard://` link, e.g. from the Shortcuts app's "Open URLs" action.
///
/// - Tiles and sets by name: `soundboard://play?title=Bonjour` (also `stop`, `fade`;
///   `&set=Effets` restricts the search to one set), `soundboard://set?title=Effets` shows a set.
/// - Every OSC address works as a path: `soundboard://transport/stopAll`,
///   `soundboard://master/volume?value=0.5`, `soundboard://set/0/tile/1/0/play`.
public enum URLCommand: Sendable, Equatable {
  public static let scheme = "soundboard"

  public enum TileAction: String, Sendable, CaseIterable {
    case play, stop, fade
  }

  case tile(title: String, set: String?, TileAction)
  case showSet(title: String)
  case osc(OSCCommand)

  public init?(_ url: URL) {
    guard url.scheme?.lowercased() == Self.scheme,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    // Values are decoded once more: a link typed with unencoded accents gets encoded twice
    // by some senders (`open` turns "%20" into "%2520"), which would leave "%20" in a name.
    let query = Dictionary(
      (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0.removingPercentEncoding ?? $0) }
      },
      uniquingKeysWith: { first, _ in first }
    )
    // soundboard://play?… puts "play" in the host; the path holds the rest.
    let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" })
      .filter { !$0.isEmpty }

    if path.count == 1, let action = TileAction(rawValue: path[0]) {
      guard let title = query["title"], !title.isEmpty else { return nil }
      self = .tile(title: title, set: query["set"], action)
      return
    }
    if path == ["set"], let title = query["title"], !title.isEmpty {
      self = .showSet(title: title)
      return
    }
    let arguments = query["value"].flatMap(Float.init).map { [OSCArgument.float($0)] } ?? []
    guard
      let command = OSCCommand(
        OSCMessage(address: "/" + path.joined(separator: "/"), arguments: arguments)
      )
    else { return nil }
    self = .osc(command)
  }

  /// Names compare like the smart set title rules: ignoring case and accents.
  public static func sameName(_ lhs: String, _ rhs: String) -> Bool {
    lhs.trimmingCharacters(in: .whitespaces).compare(
      rhs.trimmingCharacters(in: .whitespaces),
      options: [.caseInsensitive, .diacriticInsensitive]
    ) == .orderedSame
  }
}

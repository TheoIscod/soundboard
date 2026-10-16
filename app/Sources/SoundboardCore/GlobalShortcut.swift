import Foundation

/// A system-wide key combination that brings the app forward, like Farrago's
/// "Bring Farrago Forward" hotkey. It needs ⌘, ⌃ or ⌥ so it can't swallow plain typing.
public struct GlobalShortcut: Codable, Sendable, Equatable {
  public enum Modifier: String, Codable, Sendable, CaseIterable {
    case control, option, shift, command

    /// macOS menu order: ⌃ ⌥ ⇧ ⌘.
    public var symbol: String {
      switch self {
      case .control: "⌃"
      case .option: "⌥"
      case .shift: "⇧"
      case .command: "⌘"
      }
    }
  }

  /// Hardware key code, independent of the keyboard layout.
  public var keyCode: UInt32
  /// What the key shows on the user's layout, recorded with the shortcut.
  public var keyLabel: String
  public var modifiers: Set<Modifier>

  /// Nil when no ⌘, ⌃ or ⌥ is held: such a shortcut would steal plain typing everywhere.
  public init?(keyCode: UInt32, keyLabel: String, modifiers: Set<Modifier>) {
    guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
    self.keyCode = keyCode
    self.keyLabel = keyLabel
    self.modifiers = modifiers
  }

  /// E.g. "⌃⌥⌘S".
  public var displayName: String {
    Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined() + keyLabel.uppercased()
  }
}

import AppKit

/// Plays tiles from their hotkeys while the app is active. Key-down starts (or pauses with ⇧),
/// key-up releases Hold to Play tiles. Keys are left alone while text is being edited, when
/// ⌘/⌃/⌥ are held (menu shortcuts) and for auto-repeat.
@MainActor
final class KeyboardMonitor {
  private var monitor: Any?

  func install(model: BoardModel) {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
      [weak model] event in
      let handled = MainActor.assumeIsolated {
        guard let model else { return false }
        return Self.handle(event, model: model)
      }
      return handled ? nil : event
    }
  }

  private static func handle(_ event: NSEvent, model: BoardModel) -> Bool {
    if event.type == .keyDown, event.isARepeat { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.isDisjoint(with: [.command, .control, .option]),
      !(NSApp.keyWindow?.firstResponder is NSText),
      let characters = event.charactersIgnoringModifiers
    else { return false }
    return model.handleHotkey(
      characters,
      isKeyDown: event.type == .keyDown,
      shift: flags.contains(.shift)
    )
  }
}

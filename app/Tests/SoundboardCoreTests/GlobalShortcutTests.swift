import Foundation
import Testing

@testable import SoundboardCore

@Test func globalShortcutNeedsCommandControlOrOption() {
  #expect(GlobalShortcut(keyCode: 1, keyLabel: "s", modifiers: []) == nil)
  #expect(GlobalShortcut(keyCode: 1, keyLabel: "s", modifiers: [.shift]) == nil)
  #expect(GlobalShortcut(keyCode: 1, keyLabel: "s", modifiers: [.option]) != nil)
}

@Test func displayNameFollowsMenuModifierOrder() {
  let shortcut = GlobalShortcut(
    keyCode: 1,
    keyLabel: "s",
    modifiers: [.command, .shift, .option, .control]
  )

  #expect(shortcut?.displayName == "⌃⌥⇧⌘S")
}

@Test func globalShortcutRoundTripsThroughJSON() throws {
  let shortcut = try #require(
    GlobalShortcut(keyCode: 49, keyLabel: "Espace", modifiers: [.control]))

  let decoded = try JSONDecoder().decode(
    GlobalShortcut.self,
    from: JSONEncoder().encode(shortcut)
  )

  #expect(decoded == shortcut)
}

@Test func bringForwardIsAnOSCCommand() {
  #expect(OSCCommand(OSCMessage(address: "/global/bringForward")) == .bringForward)
}

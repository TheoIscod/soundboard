import AppKit
import SoundboardCore
import SwiftUI

/// Settings window: tabs for general settings and OSC.
struct SettingsView: View {
  let hotKey: GlobalHotKey
  let osc: OSCService

  var body: some View {
    TabView {
      GeneralSettingsView(hotKey: hotKey)
        .tabItem { Label("Général", systemImage: "gearshape") }
      OSCSettingsView(osc: osc)
        .tabItem { Label("OSC", systemImage: "network") }
    }
  }
}

private struct GeneralSettingsView: View {
  let hotKey: GlobalHotKey

  var body: some View {
    Form {
      Section {
        LabeledContent("Ramener Soundboard au premier plan") {
          ShortcutRecorder(hotKey: hotKey)
        }
        if let problem = hotKey.problem {
          Text(problem).foregroundStyle(.red)
        }
      } header: {
        Text("Raccourci global")
      } footer: {
        Text(
          "Fonctionne même quand une autre app est au premier plan. Il faut au moins ⌘, ⌃ ou ⌥. "
            + "Pendant l’enregistrement : Échap annule, ⌫ efface le raccourci."
        )
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 220)
  }
}

/// Click, then press the new combination.
private struct ShortcutRecorder: View {
  let hotKey: GlobalHotKey

  @State private var isRecording = false
  @State private var hint: String?
  @State private var monitor: Any?

  var body: some View {
    HStack {
      Button(label) { isRecording ? stopRecording() : startRecording() }
        .monospaced()
        .frame(minWidth: 140)
      if hotKey.shortcut != nil, !isRecording {
        Button("Effacer") { hotKey.shortcut = nil }
      }
    }
    .onDisappear { stopRecording() }
  }

  private var label: String {
    if isRecording { return hint ?? "Tapez le raccourci…" }
    return hotKey.shortcut?.displayName ?? "Aucun — cliquer pour enregistrer"
  }

  private func startRecording() {
    isRecording = true
    hint = nil
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      record(event)
      return nil
    }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
  }

  private func record(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch Int(event.keyCode) {
    case 53 where flags.isEmpty:  // Escape
      stopRecording()
      return
    case 51 where flags.isEmpty:  // Delete
      hotKey.shortcut = nil
      stopRecording()
      return
    default: break
    }
    var modifiers: Set<GlobalShortcut.Modifier> = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    let keyLabel =
      Self.specialKeyNames[Int(event.keyCode)]
      ?? event.charactersIgnoringModifiers ?? "?"
    guard
      let shortcut = GlobalShortcut(
        keyCode: UInt32(event.keyCode),
        keyLabel: keyLabel,
        modifiers: modifiers
      )
    else {
      hint = "Ajoutez ⌘, ⌃ ou ⌥"
      return
    }
    hotKey.shortcut = shortcut
    stopRecording()
  }

  /// Keys whose character is invisible or a private-use glyph.
  private static let specialKeyNames: [Int: String] = [
    49: "Espace", 36: "↩", 48: "⇥", 51: "⌫", 53: "Échap", 117: "⌦",
    123: "←", 124: "→", 125: "↓", 126: "↑",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
  ]
}

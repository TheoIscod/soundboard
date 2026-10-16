import AppKit
import SoundboardCore
import SwiftUI

/// Settings window: tabs for general settings and OSC.
struct SettingsView: View {
  let hotKey: GlobalHotKey
  let osc: OSCService
  let midiOutput: MIDIOutput

  var body: some View {
    TabView {
      GeneralSettingsView(hotKey: hotKey)
        .tabItem { Label("Général", systemImage: "gearshape") }
      MIDISettingsView(output: midiOutput)
        .tabItem { Label("MIDI", systemImage: "pianokeys") }
      OSCSettingsView(osc: osc)
        .tabItem { Label("OSC", systemImage: "network") }
    }
  }
}

private struct GeneralSettingsView: View {
  let hotKey: GlobalHotKey

  private static let links: [(String, String)] = [
    ("soundboard://play?title=Nom", "Lance la tuile (sans l’arrêter si elle joue)"),
    ("soundboard://stop?title=Nom", "Arrête la tuile"),
    ("soundboard://fade?title=Nom", "Arrête la tuile en fondu"),
    ("…&set=Nom du set", "Cherche la tuile dans ce set seulement"),
    ("soundboard://set?title=Nom", "Affiche le set"),
    ("soundboard://transport/stopAll", "Tout arrêter"),
    ("soundboard://master/volume?value=0.5", "Règle le volume général (0 à 1)"),
  ]

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

      Section {
        ForEach(Self.links, id: \.0) { link, meaning in
          LabeledContent {
            Text(meaning)
          } label: {
            Text(link).font(.body.monospaced()).textSelection(.enabled)
          }
        }
      } header: {
        Text("Liens soundboard://")
      } footer: {
        Text(
          "Dans l’app Raccourcis, utilisez l’action « Ouvrir les URL » avec ces liens. Les noms "
            + "ignorent majuscules et accents. Toutes les adresses OSC marchent aussi comme liens."
        )
      }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 520)
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

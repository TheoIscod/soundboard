import AppKit
import SwiftUI

@main
struct SoundboardApp: App {
  @State private var model = BoardModel()
  @State private var keyboard = KeyboardMonitor()

  init() {
    // Launched from `swift run` there is no app bundle, so macOS would
    // otherwise treat the process as a background tool without a Dock icon.
    NSApplication.shared.setActivationPolicy(.regular)
  }

  var body: some Scene {
    WindowGroup("Soundboard") {
      NavigationSplitView {
        SetsSidebar(model: model)
      } detail: {
        BoardView(model: model)
      }
      .onAppear { keyboard.install(model: model) }
    }
    .commands {
      CommandMenu("Playback") {
        // Farrago also accepts plain Return; ⌃Return can't clash with confirming a text field.
        Button("Play Selection") { model.playSelection() }
          .keyboardShortcut(.return, modifiers: .control)
        Button("Reset List") { model.resetList() }
          .keyboardShortcut("r", modifiers: .command)
        Divider()
        Button("Fade to Volume \(model.master.usesVolumeB ? "A" : "B")") {
          model.master.toggleAB()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Master Volume Up") { model.master.stepUp() }
          .keyboardShortcut(.upArrow, modifiers: .command)
        Button("Master Volume Down") { model.master.stepDown() }
          .keyboardShortcut(.downArrow, modifiers: .command)
        Toggle("Mute", isOn: $model.master.muted)
      }
      CommandMenu("Sound Set") {
        Button("New Set") { model.addSet() }
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Button(model.soundSet.displayMode == .list ? "Switch to Grid Mode" : "Switch to List Mode")
        {
          model.setDisplayMode(model.soundSet.displayMode == .list ? .grid : .list)
        }
        Divider()
        Button("Select Previous Set") { model.selectPreviousSet() }
          .keyboardShortcut("[", modifiers: [.command, .shift])
        Button("Select Next Set") { model.selectNextSet() }
          .keyboardShortcut("]", modifiers: [.command, .shift])
      }
    }
  }
}

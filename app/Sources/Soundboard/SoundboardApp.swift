import AppKit
import SwiftUI

@main
struct SoundboardApp: App {
  @State private var model = BoardModel()

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
    }
    .commands {
      CommandMenu("Sound Set") {
        Button("New Set") { model.addSet() }
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Divider()
        Button("Select Previous Set") { model.selectPreviousSet() }
          .keyboardShortcut("[", modifiers: [.command, .shift])
        Button("Select Next Set") { model.selectNextSet() }
          .keyboardShortcut("]", modifiers: [.command, .shift])
      }
    }
  }
}

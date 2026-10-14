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
      BoardView(model: model)
    }
  }
}

import AppKit
import SoundboardCore
import SwiftUI

@main
struct SoundboardApp: App {
  init() {
    // Launched from `swift run` there is no app bundle, so macOS would
    // otherwise treat the process as a background tool without a Dock icon.
    NSApplication.shared.setActivationPolicy(.regular)
  }

  var body: some Scene {
    WindowGroup("Soundboard") {
      BoardView(set: SoundSet(title: "Untitled Set"))
    }
  }
}

struct BoardView: View {
  let set: SoundSet

  var body: some View {
    VStack(spacing: 8) {
      Text(set.title).font(.title2)
      Text("No sounds yet").foregroundStyle(.secondary)
    }
    .frame(minWidth: 480, minHeight: 320)
  }
}

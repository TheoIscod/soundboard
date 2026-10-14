import SoundboardCore
import SwiftUI

/// Toolbar control for the master volume: A/B preset, level of the active preset, mute.
struct MasterVolumeControl: View {
  @Bindable var model: BoardModel

  var body: some View {
    HStack(spacing: 8) {
      Picker("Master preset", selection: $model.master.usesVolumeB) {
        Text("A").tag(false)
        Text("B").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .help("Master volume preset (⇧⌘D switches)")

      Slider(value: $model.master.activeVolume, in: 0...1)
        .frame(width: 110)
        .help("Master volume \(model.master.usesVolumeB ? "B" : "A") (⌘↑ / ⌘↓)")

      Text(model.master.activeVolume, format: .percent.precision(.fractionLength(0)))
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)

      Toggle(isOn: $model.master.muted) {
        Image(systemName: model.master.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
      }
      .toggleStyle(.button)
      .help("Mute everything")
    }
  }
}

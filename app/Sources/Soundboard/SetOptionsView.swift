import SoundboardCore
import SwiftUI

/// Popover with the shown set's list-mode advance options.
struct SetOptionsView: View {
  let model: BoardModel

  var body: some View {
    let set = model.soundSet
    Form {
      Picker(
        "When a sound ends",
        selection: Binding(get: { set.playbackMode }, set: { model.setPlaybackMode($0) })
      ) {
        Text("Stop").tag(PlaybackMode.single)
        Text("Select the next sound").tag(PlaybackMode.toggle)
        Text("Play the next sound").tag(PlaybackMode.continuous)
      }
      .pickerStyle(.radioGroup)

      LabeledContent("Crossfade") {
        HStack {
          Slider(
            value: Binding(
              get: { set.crossfadeDuration },
              set: { model.setCrossfadeDuration($0) }
            ),
            in: 0...10,
            step: 0.1
          )
          Text(set.crossfadeDuration.formatted(.number.precision(.fractionLength(1))) + " s")
            .monospacedDigit()
            .frame(width: 44, alignment: .trailing)
        }
      }
      .disabled(set.playbackMode != .continuous)

      Text(
        "Applies in list mode. The next sound starts this long before the end of the current one "
          + "(at most half its length) and they fade into each other."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .frame(width: 340)
  }
}

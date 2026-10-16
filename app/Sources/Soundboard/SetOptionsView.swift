import SoundboardCore
import SwiftUI

/// Popover with the shown set's list-mode advance options.
struct SetOptionsView: View {
  let model: BoardModel

  var body: some View {
    let set = model.soundSet
    Form {
      Picker(
        "À la fin d’un son",
        selection: Binding(get: { set.playbackMode }, set: { model.setPlaybackMode($0) })
      ) {
        Text("Arrêter").tag(PlaybackMode.single)
        Text("Sélectionner le son suivant").tag(PlaybackMode.toggle)
        Text("Lancer le son suivant").tag(PlaybackMode.continuous)
      }
      .pickerStyle(.radioGroup)

      LabeledContent("Fondu enchaîné") {
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
        "S’applique en mode liste. Le son suivant démarre ce temps avant la fin du son en cours "
          + "(au plus la moitié de sa durée) et les deux se fondent l’un dans l’autre."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .frame(width: 340)
  }
}

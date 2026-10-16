import CoreMIDI
import SwiftUI

/// Settings tab: which controller gets pad lights, and how they are lit.
struct MIDISettingsView: View {
  @Bindable var output: MIDIOutput

  var body: some View {
    Form {
      Section {
        Picker("Appareil", selection: $output.destinationID) {
          Text("Aucun").tag(MIDIUniqueID?.none)
          ForEach(output.destinations) { destination in
            Text(destination.name).tag(MIDIUniqueID?.some(destination.id))
          }
          if let id = output.destinationID, !output.destinations.contains(where: { $0.id == id }) {
            Text("Appareil débranché").tag(MIDIUniqueID?.some(id))
          }
        }
        LabeledContent("Vélocité « allumé »") {
          HStack {
            Slider(
              value: Binding(
                get: { Double(output.velocity) },
                set: { output.velocity = Int($0.rounded()) }
              ),
              in: 1...127
            )
            Text("\(output.velocity)")
              .monospacedDigit()
              .frame(width: 32, alignment: .trailing)
          }
        }
        .disabled(output.destinationID == nil)
      } header: {
        Text("Allumer les pads du contrôleur")
      } footer: {
        Text(
          "Quand une tuile associée à une note joue, l’app envoie cette note au contrôleur pour "
            + "allumer le pad, et l’éteint à l’arrêt. Sur beaucoup de contrôleurs à pads, la "
            + "vélocité choisit la couleur."
        )
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 260)
    .onAppear { output.refreshDestinations() }
  }
}

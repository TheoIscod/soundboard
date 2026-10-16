import SoundboardCore
import SwiftUI

/// Settings window: OSC reception, feedback output and the addresses the app understands.
struct OSCSettingsView: View {
  @Bindable var osc: OSCService

  var body: some View {
    Form {
      Section {
        Toggle("Recevoir l’OSC", isOn: $osc.inputEnabled)
        TextField("Port", value: $osc.inputPort, format: .number.grouping(.never))
          .disabled(!osc.inputEnabled)
        LabeledContent("État", value: osc.inputStatus)
      } header: {
        Text("Réception")
      } footer: {
        Text(
          "Pilotez l’app depuis un téléphone, une tablette (TouchOSC…) ou un autre logiciel sur "
            + "le même réseau. macOS peut demander l’accès au réseau local à l’activation."
        )
      }

      Section {
        Toggle("Envoyer l’état des tuiles", isOn: $osc.outputEnabled)
        TextField("Adresse", text: $osc.outputHost)
          .disabled(!osc.outputEnabled)
        TextField("Port", value: $osc.outputPort, format: .number.grouping(.never))
          .disabled(!osc.outputEnabled)
      } header: {
        Text("Envoi")
      } footer: {
        Text("Envoie …/play 1 quand une tuile démarre et 0 quand elle s’arrête.")
      }

      Section("Adresses") {
        ForEach(Self.addresses, id: \.0) { address, meaning in
          LabeledContent {
            Text(meaning)
          } label: {
            Text(address).font(.body.monospaced())
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 560)
  }

  private static let addresses: [(String, String)] = [
    (
      "/set/<n>/tile/<x>/<y>/play",
      "Lance ou arrête la tuile (set n° n, colonne x, ligne y, à partir de 0)"
    ),
    ("/set/selected/tile/<x>/<y>/…", "Même chose dans le set affiché"),
    (
      "…/fade · loop · mute · solo · toggleAB",
      "Fondu de sortie, boucle, muet, solo, volume A/B de la tuile"
    ),
    ("/master/toggleAB", "Bascule le volume général entre A et B"),
    ("/master/selectVolumeA · selectVolumeB", "Choisit le volume général A ou B"),
    ("/master/volumeUp · volumeDown", "Monte ou baisse le volume général de 5 %"),
    ("/master/volume <0…1>", "Règle le volume général"),
    ("/transport/playPauseAll", "Tout mettre en pause ou reprendre"),
    ("/transport/stopAll", "Tout arrêter"),
  ]
}

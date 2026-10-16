import SoundboardCore
import SwiftUI

/// Edits one tile; every change is saved and applied to the tile if it is playing.
struct TileInspector: View {
  let tile: Tile
  let model: BoardModel
  let onDelete: () -> Void

  var body: some View {
    Form {
      Section("Tuile") {
        TextField("Titre", text: binding(\.title))
        TextField("Icône", text: binding(\.icon), prompt: Text("Emoji"))
        Picker("Couleur", selection: binding(\.color)) {
          ForEach(TileColor.allCases, id: \.self) { color in
            Text(color.displayName).tag(color)
          }
        }
        TextField("Notes", text: binding(\.notes), axis: .vertical)
          .lineLimit(2...5)
      }

      Section {
        LabeledContent("Touche") {
          HStack {
            TextField("Touche", text: hotkeyText, prompt: Text("Aucune"))
              .labelsHidden()
              .frame(width: 60)
            if tile.hotkey != nil {
              Button("Effacer") { model.setHotkey(nil, for: tile) }
            }
          }
        }
      } header: {
        Text("Clavier")
      } footer: {
        Text(
          "Une lettre ou un chiffre lance cette tuile quand son set est affiché ; ⇧ la met en pause. "
            + "Donner la touche à une autre tuile du set la retire à celle-ci."
        )
      }

      Section("Lecture") {
        Toggle("Activée", isOn: binding(\.isEnabled))
        Toggle("Boucle", isOn: binding(\.player.loops))
        Toggle("Solo", isOn: binding(\.solo))
        Toggle("Maintenir pour jouer", isOn: binding(\.holdToPlay))
      }

      Section("Volume") {
        Picker("Joue au", selection: binding(\.player.usesVolumeB)) {
          Text("Volume A").tag(false)
          Text("Volume B").tag(true)
        }
        .pickerStyle(.segmented)
        percentSlider("Volume A", value: binding(\.player.volumeA))
        percentSlider("Volume B", value: binding(\.player.volumeB))
        Toggle("Muet", isOn: binding(\.player.muted))
      }

      if let duration = model.duration(of: tile) {
        Section {
          WaveformEditor(tile: tile, duration: duration, model: model)
          LabeledContent("Début", value: Self.format(tile.player.trimStart))
          LabeledContent("Fin", value: Self.format(duration - tile.player.trimEnd))
          LabeledContent("Fondu d’entrée", value: Self.format(tile.player.fadeInTime))
          LabeledContent("Fondu de sortie", value: Self.format(tile.player.fadeOutTime))
        } header: {
          Text("Découpe et fondus")
        } footer: {
          Text(
            "Faites glisser les barres pour découper et les points jaunes pour régler les fondus. "
              + "Durée du son : \(Self.format(duration)). La découpe et la boucle s’appliquent "
              + "au prochain lancement."
          )
        }
      } else {
        Section {
          Text("Le fichier son est illisible : découpe et fondus indisponibles.")
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button("Supprimer la tuile…", role: .destructive, action: onDelete)
      }
    }
    .formStyle(.grouped)
  }

  /// Shows the key uppercased; typing replaces it with the last character typed.
  private var hotkeyText: Binding<String> {
    Binding(
      get: { tile.hotkey?.uppercased() ?? "" },
      set: { text in model.setHotkey(text.last.map(String.init), for: tile) }
    )
  }

  private func percentSlider(_ label: String, value: Binding<Float>) -> some View {
    LabeledContent(label) {
      HStack {
        Slider(value: value, in: 0...1)
        Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
          .monospacedDigit()
          .frame(width: 44, alignment: .trailing)
      }
    }
  }

  private static func format(_ seconds: TimeInterval) -> String {
    seconds.formatted(.number.precision(.fractionLength(2))) + " s"
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<Tile, Value>) -> Binding<Value> {
    model.binding(for: tile, keyPath)
  }
}

extension BoardModel {
  /// A binding to one field of a tile that saves the edited tile on every change.
  func binding<Value>(for tile: Tile, _ keyPath: WritableKeyPath<Tile, Value>) -> Binding<Value> {
    Binding(
      get: { tile[keyPath: keyPath] },
      set: { newValue in
        var updated = tile
        updated[keyPath: keyPath] = newValue
        self.update(updated)
      }
    )
  }
}

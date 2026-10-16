import SoundboardCore
import SwiftUI

/// Edits one tile; every change is saved and applied to the tile if it is playing.
struct TileInspector: View {
  let tile: Tile
  let model: BoardModel
  let onDelete: () -> Void

  var body: some View {
    Form {
      Section("Tile") {
        TextField("Title", text: binding(\.title))
        TextField("Icon", text: binding(\.icon), prompt: Text("Emoji"))
        Picker("Color", selection: binding(\.color)) {
          ForEach(TileColor.allCases, id: \.self) { color in
            Text(color.displayName).tag(color)
          }
        }
        TextField("Notes", text: binding(\.notes), axis: .vertical)
          .lineLimit(2...5)
      }

      Section {
        LabeledContent("Key") {
          HStack {
            TextField("Key", text: hotkeyText, prompt: Text("None"))
              .labelsHidden()
              .frame(width: 60)
            if tile.hotkey != nil {
              Button("Clear") { model.setHotkey(nil, for: tile) }
            }
          }
        }
      } header: {
        Text("Keyboard")
      } footer: {
        Text(
          "A letter or digit plays this tile while its set is shown; ⇧ pauses it. "
            + "Giving a key to another tile of the set takes it from this one."
        )
      }

      Section("Playback") {
        Toggle("Enabled", isOn: binding(\.isEnabled))
        Toggle("Loop", isOn: binding(\.player.loops))
        Toggle("Solo", isOn: binding(\.solo))
        Toggle("Hold to Play", isOn: binding(\.holdToPlay))
      }

      Section("Volume") {
        Picker("Plays at", selection: binding(\.player.usesVolumeB)) {
          Text("Volume A").tag(false)
          Text("Volume B").tag(true)
        }
        .pickerStyle(.segmented)
        percentSlider("Volume A", value: binding(\.player.volumeA))
        percentSlider("Volume B", value: binding(\.player.volumeB))
        Toggle("Mute", isOn: binding(\.player.muted))
      }

      if let duration = model.duration(of: tile) {
        Section {
          WaveformEditor(tile: tile, duration: duration, model: model)
          LabeledContent("Start", value: Self.format(tile.player.trimStart))
          LabeledContent("End", value: Self.format(duration - tile.player.trimEnd))
          LabeledContent("Fade in", value: Self.format(tile.player.fadeInTime))
          LabeledContent("Fade out", value: Self.format(tile.player.fadeOutTime))
        } header: {
          Text("Trim & Fades")
        } footer: {
          Text(
            "Drag the bars to trim and the yellow dots to set the fades. "
              + "Sound length \(Self.format(duration)). Trim and Loop apply the next time it starts."
          )
        }
      } else {
        Section {
          Text("The sound file can’t be read, so fades and trim are unavailable.")
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button("Delete Tile…", role: .destructive, action: onDelete)
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

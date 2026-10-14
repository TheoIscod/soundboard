import SoundboardCore
import SwiftUI

/// Edits one tile; every change is saved and applied to the tile if it is playing.
struct TileInspector: View {
  let tile: Tile
  let model: BoardModel
  let onDelete: () -> Void

  /// Keeps at least this much sound between the two trim points.
  private static let minimumPlayableLength: TimeInterval = 0.1

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
        Section("Fades") {
          secondsSlider("Fade in", value: binding(\.player.fadeInTime), upTo: duration / 2)
          secondsSlider("Fade out", value: binding(\.player.fadeOutTime), upTo: duration / 2)
        }

        Section {
          secondsSlider(
            "Start",
            value: binding(\.player.trimStart),
            upTo: max(duration - tile.player.trimEnd - Self.minimumPlayableLength, 0)
          )
          secondsSlider(
            "End",
            value: binding(\.player.trimEnd),
            upTo: max(duration - tile.player.trimStart - Self.minimumPlayableLength, 0)
          )
        } header: {
          Text("Trim")
        } footer: {
          Text(
            "Sound length \(Self.format(duration)). Trim and Loop apply the next time it starts.")
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

  private func secondsSlider(
    _ label: String,
    value: Binding<TimeInterval>,
    upTo limit: TimeInterval
  ) -> some View {
    LabeledContent(label) {
      HStack {
        Slider(value: value, in: 0...max(limit, 0.01))
          .disabled(limit <= 0)
        Text(Self.format(value.wrappedValue))
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
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

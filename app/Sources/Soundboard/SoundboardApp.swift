import AppKit
import SwiftUI

@main
struct SoundboardApp: App {
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
  @State private var model = BoardModel()
  @State private var keyboard = KeyboardMonitor()
  @State private var midi = MIDIInput()
  @State private var hotKey = GlobalHotKey()

  init() {
    // Launched from `swift run` there is no app bundle, so macOS would
    // otherwise treat the process as a background tool without a Dock icon.
    NSApplication.shared.setActivationPolicy(.regular)
  }

  var body: some Scene {
    WindowGroup("Soundboard") {
      NavigationSplitView {
        SetsSidebar(model: model)
      } detail: {
        BoardView(model: model)
      }
      // On the split view rather than the board, so it gets its own full-height column
      // and the board's toolbar stops at its edge instead of running over it.
      .inspector(isPresented: $model.isInspectorPresented) {
        Group {
          if let tile = model.selectedTile {
            TileInspector(
              tile: tile,
              model: model,
              onDelete: model.soundSet.isSmart ? nil : { model.tilePendingDeletion = tile }
            )
          } else {
            ContentUnavailableView("Aucune tuile sélectionnée", systemImage: "square.dashed")
          }
        }
        .inspectorColumnWidth(min: 260, ideal: 300)
      }
      .sheet(
        isPresented: Binding(
          get: { model.rulesEditorSetID != nil },
          set: { if !$0 { model.rulesEditorSetID = nil } }
        )
      ) {
        if let id = model.rulesEditorSetID, let set = model.library.set(withID: id) {
          SmartRulesEditor(set: set, model: model)
        }
      }
      .onAppear {
        keyboard.install(model: model)
        midi.install(model: model)
        appDelegate.openHandler = { [model] urls in model.open(urls) }
        appDelegate.terminateHandler = { [model] in model.flushSaves() }
      }
    }
    .commands {
      EditorCommands(model: model)
      CommandMenu("Lecture") {
        // Farrago also accepts plain Return; ⌃Return can't clash with confirming a text field.
        Button("Jouer la sélection") { model.playSelection() }
          .keyboardShortcut(.return, modifiers: .control)
        Button("Réinitialiser la liste") { model.resetList() }
          .keyboardShortcut("r", modifiers: .command)
        Divider()
        Button("Fondu vers le volume \(model.master.usesVolumeB ? "A" : "B")") {
          model.master.toggleAB()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Monter le volume général") { model.master.stepUp() }
          .keyboardShortcut(.upArrow, modifiers: .command)
        Button("Baisser le volume général") { model.master.stepDown() }
          .keyboardShortcut(.downArrow, modifiers: .command)
        Toggle("Tout couper", isOn: $model.master.muted)
      }
      CommandMenu("MIDI") {
        Button("Apprendre le MIDI") { model.startMIDILearn() }
          .keyboardShortcut("l", modifiers: .command)
          .disabled(model.selectedTile == nil)
        Button("Annuler l’apprentissage") { model.cancelMIDILearn() }
          .disabled(model.midiLearningTileID == nil)
        Button("Effacer le MIDI") {
          if let tile = model.selectedTile { model.clearMIDI(for: tile) }
        }
        .disabled(model.selectedTile?.midiTrigger == nil)
      }
      CommandMenu("Set") {
        Button("Nouveau set") { model.addSet() }
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Nouveau smart set") { model.addSmartSet() }
          .keyboardShortcut("n", modifiers: [.command, .option])
        Button("Modifier les règles…") { model.rulesEditorSetID = model.soundSet.id }
          .disabled(!model.soundSet.isSmart)
        Button(
          model.soundSet.displayMode == .list ? "Passer en mode grille" : "Passer en mode liste"
        ) {
          model.setDisplayMode(model.soundSet.displayMode == .list ? .grid : .list)
        }
        Divider()
        Button("Importer des sets…") { model.importSets(from: SetFiles.chooseSetsToImport()) }
        Button("Exporter le set…") {
          if let destination = SetFiles.chooseExportDestination(for: model.soundSet) {
            model.exportShownSet(to: destination)
          }
        }
        Divider()
        Button("Set précédent") { model.selectPreviousSet() }
          .keyboardShortcut("[", modifiers: [.command, .shift])
        Button("Set suivant") { model.selectNextSet() }
          .keyboardShortcut("]", modifiers: [.command, .shift])
      }
    }

    WindowGroup("Éditeur", id: EditorWindow.id, for: UUID.self) { $tileID in
      if let tileID {
        WaveformEditorWindow(tileID: tileID, model: model)
      }
    }
    .defaultSize(width: 980, height: 440)

    Settings {
      SettingsView(hotKey: hotKey, osc: model.osc, midiOutput: model.midiOutput)
    }
  }
}

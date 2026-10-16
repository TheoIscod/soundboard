import SoundboardCore
import SwiftUI

struct SetsSidebar: View {
  let model: BoardModel

  @State private var renamingSetID: UUID?
  @State private var draftTitle = ""
  @State private var setPendingDeletion: SoundSet?
  @FocusState private var isRenameFieldFocused: Bool

  var body: some View {
    List(selection: selection) {
      ForEach(model.library.sets) { set in
        row(for: set)
          .tag(set.id)
          .contextMenu {
            Button("Renommer") { beginRenaming(set) }
            if set.isSmart {
              Button("Modifier les règles…") { model.rulesEditorSetID = set.id }
            }
            Button("Supprimer…", role: .destructive) { setPendingDeletion = set }
              .disabled(!model.canDeleteSet())
          }
      }
    }
    .navigationSplitViewColumnWidth(min: 160, ideal: 200)
    .toolbar {
      Button("Nouveau set", systemImage: "plus") { model.addSet() }
    }
    .confirmationDialog(
      "Supprimer « \(setPendingDeletion?.title ?? "") » ?",
      isPresented: Binding(
        get: { setPendingDeletion != nil },
        set: { if !$0 { setPendingDeletion = nil } }
      )
    ) {
      Button("Supprimer le set", role: .destructive) {
        if let set = setPendingDeletion { model.deleteSet(set.id) }
        setPendingDeletion = nil
      }
    } message: {
      Text(
        "Ses tuiles et les copies de leurs sons seront supprimées. Cette action est irréversible.")
    }
  }

  private var selection: Binding<UUID?> {
    Binding(
      get: { model.library.selectedSetID },
      set: { if let id = $0 { model.selectSet(id) } }
    )
  }

  @ViewBuilder
  private func row(for set: SoundSet) -> some View {
    if renamingSetID == set.id {
      TextField("Nom du set", text: $draftTitle)
        .focused($isRenameFieldFocused)
        .onSubmit { commitRename() }
        .onChange(of: isRenameFieldFocused) { _, focused in
          if !focused { commitRename() }
        }
        .onExitCommand { renamingSetID = nil }
    } else {
      Label {
        Text(set.title)
      } icon: {
        Image(systemName: set.isSmart ? "gearshape.fill" : "square.grid.3x3.fill")
      }
      .badge(model.library.shownSet(set, gridColumns: BoardModel.gridColumns).tiles.count)
      .onTapGesture(count: 2) { beginRenaming(set) }
    }
  }

  private func beginRenaming(_ set: SoundSet) {
    draftTitle = set.title
    renamingSetID = set.id
    isRenameFieldFocused = true
  }

  private func commitRename() {
    guard let id = renamingSetID else { return }
    renamingSetID = nil
    model.renameSet(id, to: draftTitle)
  }
}

import SoundboardCore
import SwiftUI

/// Sheet editing a smart set's rules on a copy: OK applies them, Cancel drops them.
struct SmartRulesEditor: View {
  let set: SoundSet
  let model: BoardModel

  @State private var rules: SmartRules
  @Environment(\.dismiss) private var dismiss

  init(set: SoundSet, model: BoardModel) {
    self.set = set
    self.model = model
    _rules = State(initialValue: set.smartRules ?? SmartRules())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Règles de « \(set.title) »").font(.headline)

      HStack {
        Text("Montrer les tuiles qui suivent")
        Picker("Correspondance", selection: $rules.match) {
          Text("toutes les règles").tag(SmartRules.Match.all)
          Text("au moins une règle").tag(SmartRules.Match.any)
        }
        .labelsHidden()
        .fixedSize()
      }

      VStack(spacing: 8) {
        ForEach(rules.rules.indices, id: \.self) { index in
          RuleRow(rule: rule(at: index)) {
            rules.rules.remove(at: index)
          }
        }
      }

      Button("Ajouter une règle", systemImage: "plus") {
        rules.rules.append(.flag(.favorite, is: true))
      }

      Text(
        "\(matchingCount) tuile\(matchingCount > 1 ? "s" : "") des sets normaux "
          + "correspond\(matchingCount > 1 ? "ent" : "") à ces règles."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("Annuler", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("OK") {
          model.setRules(rules, forSet: set.id)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 560)
  }

  /// Bounds-checked: SwiftUI can still read a row's binding while removing that row.
  private func rule(at index: Int) -> Binding<SmartRule> {
    Binding(
      get: {
        rules.rules.indices.contains(index) ? rules.rules[index] : .flag(.favorite, is: true)
      },
      set: { if rules.rules.indices.contains(index) { rules.rules[index] = $0 } }
    )
  }

  private var matchingCount: Int {
    model.library.sets.filter { !$0.isSmart }.flatMap(\.tiles).filter(rules.matches).count
  }
}

/// One rule: subject, then a comparison or value that depends on the subject.
private struct RuleRow: View {
  @Binding var rule: SmartRule
  let onRemove: () -> Void

  private enum Subject: Hashable {
    case title
    case color
    case flag(SmartRule.Flag)
  }

  var body: some View {
    HStack {
      Picker("Critère", selection: subject) {
        Text("Titre").tag(Subject.title)
        Text("Couleur").tag(Subject.color)
        Divider()
        ForEach(SmartRule.Flag.allCases, id: \.self) { flag in
          Text(Self.name(of: flag)).tag(Subject.flag(flag))
        }
      }
      .labelsHidden()
      .frame(width: 180)

      switch rule {
      case .title(let comparison, let text):
        Picker(
          "Comparaison",
          selection: Binding(get: { comparison }, set: { rule = .title($0, text) })
        ) {
          Text("contient").tag(SmartRule.TextComparison.contains)
          Text("commence par").tag(SmartRule.TextComparison.beginsWith)
          Text("finit par").tag(SmartRule.TextComparison.endsWith)
        }
        .labelsHidden()
        .fixedSize()
        TextField("Texte", text: Binding(get: { text }, set: { rule = .title(comparison, $0) }))
      case .color(let color):
        Text("est")
        Picker("Couleur", selection: Binding(get: { color }, set: { rule = .color($0) })) {
          ForEach(TileColor.allCases, id: \.self) { color in
            Text(color.displayName).tag(color)
          }
        }
        .labelsHidden()
        .fixedSize()
      case .flag(let flag, let expected):
        Picker(
          "Valeur",
          selection: Binding(get: { expected }, set: { rule = .flag(flag, is: $0) })
        ) {
          Text("oui").tag(true)
          Text("non").tag(false)
        }
        .labelsHidden()
        .fixedSize()
      }

      Spacer()
      Button("Retirer la règle", systemImage: "minus.circle", action: onRemove)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
  }

  /// Changing the subject resets the rule to that subject's default.
  private var subject: Binding<Subject> {
    Binding(
      get: {
        switch rule {
        case .title: .title
        case .color: .color
        case .flag(let flag, _): .flag(flag)
        }
      },
      set: { subject in
        switch subject {
        case .title: rule = .title(.contains, "")
        case .color: rule = .color(.purple)
        case .flag(let flag): rule = .flag(flag, is: true)
        }
      }
    )
  }

  private static func name(of flag: SmartRule.Flag) -> String {
    switch flag {
    case .favorite: "Favori"
    case .loops: "Boucle"
    case .holdToPlay: "Maintenir pour jouer"
    case .solo: "Solo"
    case .played: "Déjà joué"
    }
  }
}

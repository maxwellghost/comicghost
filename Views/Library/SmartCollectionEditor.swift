import SwiftUI
import SwiftData

/// Build or edit a saved filter.
struct SmartCollectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    /// nil when creating a new collection.
    var existing: SmartCollection?
    var previewItems: [LibraryItem] = []

    @State private var name = ""
    @State private var icon = "line.3.horizontal.decrease.circle"
    @State private var matchAll = true
    @State private var rules: [SmartRule] = []

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private let iconChoices = [
        "line.3.horizontal.decrease.circle", "star", "flame", "bolt",
        "bookmark", "tag", "sparkles", "clock", "eye", "crown",
    ]

    private var matchCount: Int {
        let probe = SmartCollection(name: "", matchAll: matchAll, rules: rules)
        return probe.matches(previewItems).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New Smart Collection" : "Edit Smart Collection")
                .font(.headline)
                .foregroundStyle(CGTheme.text)

            HStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    ForEach(iconChoices, id: \.self) { choice in
                        Button {
                            icon = choice
                        } label: {
                            Label(choice, systemImage: choice)
                        }
                    }
                } label: {
                    Image(systemName: icon)
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 22)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 44)
            }

            HStack(spacing: 8) {
                Text("Match")
                    .foregroundStyle(CGTheme.subtext1)
                Picker("", selection: $matchAll) {
                    Text("all").tag(true)
                    Text("any").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                Text("of the following:")
                    .foregroundStyle(CGTheme.subtext1)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach($rules) { $rule in
                    ruleRow($rule)
                }
            }

            Button {
                rules.append(SmartRule(field: .status, comparison: .equals, value: "Unread"))
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
                    .font(.callout)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            Divider().overlay(CGTheme.surface1)

            Text("\(matchCount) issue\(matchCount == 1 ? "" : "s") match right now")
                .font(.caption)
                .foregroundStyle(CGTheme.subtext0)

            HStack {
                if let existing {
                    Button("Delete", role: .destructive) {
                        context.delete(existing)
                        try? context.save()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(CGTheme.base)
        .onAppear { load() }
    }

    private func ruleRow(_ rule: Binding<SmartRule>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: rule.field) {
                ForEach(SmartRule.Field.allCases) { field in
                    Text(field.label).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .onChange(of: rule.wrappedValue.field) { _, newField in
                let options = SmartRule.Comparison.options(for: newField.kind)
                if !options.contains(rule.wrappedValue.comparison) {
                    rule.wrappedValue.comparison = options.first ?? .equals
                }
                rule.wrappedValue.value = defaultValue(for: newField)
            }

            Picker("", selection: rule.comparison) {
                ForEach(SmartRule.Comparison.options(for: rule.wrappedValue.field.kind)) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            valueField(rule)

            Button {
                rules.removeAll { $0.id == rule.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(CGTheme.subtext0)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func valueField(_ rule: Binding<SmartRule>) -> some View {
        switch rule.wrappedValue.field.kind {
        case .status:
            Picker("", selection: rule.value) {
                ForEach(SmartRule.statusOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        case .boolean:
            Picker("", selection: rule.value) {
                Text("yes").tag("true")
                Text("no").tag("false")
            }
            .labelsHidden()
        case .number, .days:
            HStack(spacing: 4) {
                TextField("0", text: rule.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                if rule.wrappedValue.field == .dateAdded {
                    Text("days ago").font(.caption).foregroundStyle(CGTheme.subtext0)
                }
            }
        case .text:
            TextField("Value", text: rule.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func defaultValue(for field: SmartRule.Field) -> String {
        switch field.kind {
        case .status: return "Unread"
        case .boolean: return "true"
        case .number: return "3"
        case .days: return "30"
        case .text: return ""
        }
    }

    private func load() {
        guard let existing else {
            if rules.isEmpty {
                rules = [SmartRule(field: .status, comparison: .equals, value: "Unread")]
            }
            return
        }
        name = existing.name
        icon = existing.icon
        matchAll = existing.matchAll
        rules = existing.rules
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.name = clean
            existing.icon = icon
            existing.matchAll = matchAll
            existing.rules = rules
        } else {
            let collection = SmartCollection(
                name: clean, icon: icon, matchAll: matchAll, rules: rules,
                sortIndex: Int(Date.now.timeIntervalSince1970)
            )
            context.insert(collection)
        }
        try? context.save()
        dismiss()
    }
}

import SwiftUI

/// Assigns a franchise to an entire series in one action.
///
/// Setting this per-issue through the metadata editor is fine for a one-shot
/// and unusable for a 500-issue run, which is what this is for.
struct SeriesGroupSheet: View {
    enum Field {
        case seriesGroup
        case publisher

        var title: String {
            switch self {
            case .seriesGroup: return "Series Group"
            case .publisher: return "Publisher"
            }
        }

        var placeholder: String {
            switch self {
            case .seriesGroup: return "e.g. X-Men"
            case .publisher: return "e.g. Marvel"
            }
        }

        var explanation: String {
            switch self {
            case .seriesGroup: return "Groups related series together in the sidebar."
            case .publisher: return "The top level of the sidebar tree."
            }
        }

        var existingLabel: String {
            switch self {
            case .seriesGroup: return "Existing groups"
            case .publisher: return "Existing publishers"
            }
        }

        var removeLabel: String {
            switch self {
            case .seriesGroup: return "Remove from Group"
            case .publisher: return "Clear Publisher"
            }
        }
    }

    var field: Field = .seriesGroup
    let seriesName: String
    let issueCount: Int
    /// Values already in use, offered as suggestions.
    let existingGroups: [String]
    let currentGroup: String?
    /// Overrides the "all N issues of X" sentence. Set this when the target is
    /// a hand-picked selection rather than one whole series.
    var scopeDescription: String? = nil

    var onApply: (String?) -> Void
    var onCancel: () -> Void

    @State private var draft = ""
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    private var accent: Color { CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve }

    private var scopeSentence: String {
        scopeDescription ?? "Applies to all \(issueCount) issues of \(seriesName)."
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Suggestions that still match what's been typed.
    private var suggestions: [String] {
        let others = existingGroups.filter { $0 != trimmed }
        guard !trimmed.isEmpty else { return Array(others.prefix(8)) }
        return others
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.title)
                    .font(.headline)
                    .foregroundStyle(CGTheme.text)
                Text("\(field.explanation) \(scopeSentence)")
                    .font(.caption)
                    .foregroundStyle(CGTheme.subtext0)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(field.placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onApply(trimmed.isEmpty ? nil : trimmed) }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.existingLabel)
                        .font(.caption2)
                        .foregroundStyle(CGTheme.subtext0)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(suggestions, id: \.self) { name in
                                Button { draft = name } label: {
                                    Text(name)
                                        .font(.callout)
                                        .foregroundStyle(CGTheme.subtext1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(CGTheme.surface0.opacity(0.5))
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Text("Stored in Comic Ghost only — your files aren't modified. Undo with Cmd+Z.")
                .font(.caption2)
                .foregroundStyle(CGTheme.subtext0.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if currentGroup != nil {
                    Button(field.removeLabel) { onApply(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(CGTheme.red)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { onApply(trimmed.isEmpty ? nil : trimmed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty && currentGroup == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(CGTheme.base)
        .onAppear { draft = currentGroup ?? "" }
    }
}

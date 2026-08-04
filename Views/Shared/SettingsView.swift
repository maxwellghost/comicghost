import SwiftUI

struct SettingsView: View {
    @AppStorage(WatchedFolder.pathKey) private var watchedFolderPath: String = ""
    @AppStorage(CGGlass.key) private var glassEnabled: Bool = true
    @AppStorage("restoreWindowState") private var restoreState: Bool = true
    @AppStorage("autoHideChrome") private var autoHideChrome: Bool = true
    @AppStorage(CGAccent.key) private var accentRaw: String = CGAccent.mauve.rawValue

    private var accent: Color {
        CGAccent(rawValue: accentRaw)?.color ?? CGTheme.mauve
    }

    var body: some View {
        Form {
            Section("Library") {
                HStack {
                    Text(watchedFolderPath.isEmpty ? "No folder selected" : watchedFolderPath)
                        .foregroundStyle(watchedFolderPath.isEmpty ? CGTheme.subtext0 : CGTheme.text)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose Folder…") { chooseFolder() }
                }
            }

            Section("Appearance") {
                Toggle(isOn: $glassEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glass effect")
                        Text("Frosted translucency in the sidebar and around comic pages.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                    HStack(spacing: 10) {
                        ForEach(CGAccent.allCases) { option in
                            Button {
                                accentRaw = option.rawValue
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                accentRaw == option.rawValue
                                                    ? CGTheme.text : .clear,
                                                lineWidth: 2
                                            )
                                            .padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(option.label)
                        }
                    }
                }
            }

            Section("Behavior") {
                Toggle(isOn: $restoreState) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember where I was")
                        Text("Reopen to the section and series you were last browsing.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Toggle(isOn: $autoHideChrome) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-hide reader controls")
                        Text("Fade the page counter and buttons while you read.")
                            .font(.caption)
                            .foregroundStyle(CGTheme.subtext0)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540)
        .background(CGTheme.base)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            WatchedFolder.save(url: url)
        }
    }
}

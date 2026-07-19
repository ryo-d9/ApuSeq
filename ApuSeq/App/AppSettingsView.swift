import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppSettingsView: View {
    @AppStorage("alignmentFontSize") private var alignmentFontSize = 12.0
    @AppStorage("identityColorThreshold") private var identityColorThreshold = 0.5
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("showEditModeAutosaveWarning") private var showEditModeAutosaveWarning = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            appearanceSettings
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            editingSettings
                .tabItem {
                    Label("Editing", systemImage: "pencil")
                }
        }
        .padding(20)
        .frame(width: 500, height: 280)
        .preferredColorScheme((AppAppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme)
    }

    private var generalSettings: some View {
        Form {
            Section("Alignment") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Font Size") {
                        HStack {
                            Slider(value: $alignmentFontSize, in: 8...24, step: 1)
                                .frame(width: 220)
                            Text("\(Int(alignmentFontSize)) pt")
                                .frame(width: 56, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Identity Threshold") {
                        HStack {
                            Slider(value: $identityColorThreshold, in: 0.1...0.9, step: 0.01)
                                .frame(width: 220)
                            Text("\(Int(identityColorThreshold * 100))%")
                                .frame(width: 56, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Translation") {
                Picker("Codon Table", selection: $translationCodonTable) {
                    ForEach(TranslationCodonTable.allCases) { table in
                        Text(table.displayName).tag(table.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Choose whether ApuSeq follows the system appearance or uses a fixed light or dark appearance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var editingSettings: some View {
        Form {
            Section("Edit Mode") {
                Toggle("Edit Mode Warning", isOn: $showEditModeAutosaveWarning)

                Text("Show a warning before entering Edit mode because edits can be autosaved with document versions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

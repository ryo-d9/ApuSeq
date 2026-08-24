import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var localizedName: String {
        AppStrings.appearanceName(self)
    }

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
    private static let alignmentFontSizeRange = 8.0...24.0
    private static let identityThresholdRange = 0.1...0.9
    private static let identityThresholdTicks = Array(stride(from: 0.1, through: 0.9, by: 0.1))

    @AppStorage("alignmentFontSize") private var alignmentFontSize = 12.0
    @AppStorage("identityColorThreshold") private var identityColorThreshold = 0.5
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("showEditModeAutosaveWarning") private var showEditModeAutosaveWarning = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gearshape")
                }

            appearanceSettings
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "paintbrush")
                }

            editingSettings
                .tabItem {
                    Label(String(localized: "Editing"), systemImage: "pencil")
                }
        }
        .padding(20)
        .frame(width: 540, height: 280)
        .preferredColorScheme((AppAppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme)
    }

    private var generalSettings: some View {
        Form {
            Section(String(localized: "Alignment")) {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent(String(localized: "Font Size")) {
                        HStack {
                            Slider(value: alignmentFontSizeBinding, in: Self.alignmentFontSizeRange, step: 1)
                                .frame(width: 220)
                            HStack(spacing: 4) {
                                TextField(
                                    value: alignmentFontSizeBinding,
                                    format: .number.precision(.fractionLength(0)),
                                    prompt: Text(12, format: .number),
                                    label: EmptyView.init
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 42)
                                    .multilineTextAlignment(.trailing)
                                Text("pt")
                                    .foregroundStyle(.secondary)
                            }
                                .frame(width: 64, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }

                    LabeledContent(String(localized: "Identity Threshold")) {
                        HStack {
                            Slider(value: identityColorThresholdBinding, in: Self.identityThresholdRange) {
                                EmptyView()
                            } ticks: {
                                SliderTickContentForEach(Self.identityThresholdTicks, id: \.self) { value in
                                    SliderTick(value)
                                }
                            }
                                .frame(width: 220)
                            HStack(spacing: 4) {
                                TextField(
                                    value: identityColorThresholdPercentageBinding,
                                    format: .number,
                                    prompt: Text(50, format: .number),
                                    label: EmptyView.init
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 42)
                                    .multilineTextAlignment(.trailing)
                                Text("%")
                                    .foregroundStyle(.secondary)
                            }
                                .frame(width: 64, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section(String(localized: "Translation")) {
                Picker(String(localized: "Genetic Code"), selection: $translationCodonTable) {
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
            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Appearance"), selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }

    private var editingSettings: some View {
        Form {
            Section(String(localized: "Edit Mode")) {
                Toggle(String(localized: "Edit Mode Warning"), isOn: $showEditModeAutosaveWarning)

                Text(String(localized: "Show a warning before entering Edit mode because edits are autosaved."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var alignmentFontSizeBinding: Binding<Double> {
        Binding(
            get: {
                min(max(alignmentFontSize, Self.alignmentFontSizeRange.lowerBound), Self.alignmentFontSizeRange.upperBound)
            },
            set: { newValue in
                let roundedValue = newValue.rounded()
                alignmentFontSize = min(max(roundedValue, Self.alignmentFontSizeRange.lowerBound), Self.alignmentFontSizeRange.upperBound)
            }
        )
    }

    private var identityColorThresholdBinding: Binding<Double> {
        Binding(
            get: {
                min(max(identityColorThreshold, Self.identityThresholdRange.lowerBound), Self.identityThresholdRange.upperBound)
            },
            set: { newValue in
                let roundedValue = (newValue * 100).rounded() / 100
                identityColorThreshold = min(max(roundedValue, Self.identityThresholdRange.lowerBound), Self.identityThresholdRange.upperBound)
            }
        )
    }

    private var identityColorThresholdPercentage: Int {
        Int((identityColorThresholdBinding.wrappedValue * 100).rounded())
    }

    private var identityColorThresholdPercentageBinding: Binding<Int> {
        Binding(
            get: {
                identityColorThresholdPercentage
            },
            set: { newValue in
                identityColorThresholdBinding.wrappedValue = Double(newValue) / 100
            }
        )
    }
}

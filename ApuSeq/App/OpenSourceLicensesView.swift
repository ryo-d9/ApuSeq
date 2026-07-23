import SwiftUI

struct OpenSourceLicensesView: View {
    static let windowID = "open-source-licenses"

    private let mafftLicense = ThirdPartyLicense(
        name: "MAFFT",
        version: "7.526 (2024/Apr/26)",
        description: String(localized: "Multiple sequence alignment program"),
        copyright: "Copyright (c) 2006 Kazutaka Katoh",
        licenseName: "BSD License",
        websiteURL: URL(string: "https://mafft.cbrc.jp/alignment/software/")!,
        resourceName: "LICENSE-MAFFT"
    )

    var body: some View {
        Form {
            Section(AppStrings.openSourceLicenses) {
                ThirdPartyLicenseView(item: mafftLicense)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 380)
        .navigationTitle(AppStrings.openSourceLicenses)
    }
}

private struct ThirdPartyLicense: Identifiable {
    var id: String { name }

    let name: String
    let version: String?
    let description: String
    let copyright: String
    let licenseName: String
    let websiteURL: URL
    let resourceName: String
}

private struct ThirdPartyLicenseView: View {
    let item: ThirdPartyLicense

    @State private var licenseText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name)
                    .font(.headline)

                Link(AppStrings.website, destination: item.websiteURL)
                    .font(.caption)
            }

            Text(item.description)
                .foregroundStyle(.secondary)

            if let version = item.version {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup(item.licenseName) {
                ScrollView {
                    Text(licenseText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(minHeight: 180)
                .onAppear {
                    loadLicenseTextIfNeeded()
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadLicenseTextIfNeeded() {
        guard licenseText.isEmpty else { return }
        licenseText = LicenseResourceLoader.text(named: item.resourceName)
    }
}

private enum LicenseResourceLoader {
    static func text(named resourceName: String) -> String {
        let candidateURLs = [
            Bundle.main.url(forResource: resourceName, withExtension: "txt"),
            Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Licenses"),
            Bundle.main.url(forResource: resourceName, withExtension: "txt", subdirectory: "Resources/Licenses")
        ]

        for url in candidateURLs.compactMap(\.self) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        return String(localized: "License text could not be loaded.")
    }
}

#Preview {
    OpenSourceLicensesView()
}

import AppKit
import SwiftUI

struct AboutApuSeqView: View {
    static let windowID = "about-apuseq"

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.fill.quaternary)
                    .ignoresSafeArea(.container, edges: .top)

                AboutSummaryView()
            }
            .frame(width: 200)

            Rectangle()
                .fill(.separator)
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.openSourceLicenses)
                        .font(.headline)

                    Text(AppStrings.openSourceLicensesDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                OpenSourceLicensesPane()
            }
            .frame(width: 340)
        }
        .frame(height: 300)
        .controlSize(.small)
        .accessibilityIdentifier("about-apuseq-window-content")
    }
}

private struct AboutSummaryView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityLabel("ApuSeq")

            Text("ApuSeq")
                .font(.title)

            Text(String(localized: "Version \(appVersion)"))
                .foregroundStyle(.secondary)

            if let copyright {
                Text(copyright)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("about-summary-pane")
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "-"
        }
    }

    private var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }
}

#Preview {
    AboutApuSeqView()
}

//
//  ApuSeqApp.swift
//  ApuSeq
//
//  Created by Ryo Suda on 2026/04/27.
//

import SwiftUI

@main
struct ApuSeqApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ApuSeqDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            TextEditingCommands()
            AlignmentCommands()
            ViewerModeCommands()
            ViewPanelCommands()
            ColumnSelectionCommands()
            SequenceNameCommands()
            AlignmentEditCommands()
            InspectorCommands()
            OpenSourceLicenseCommands()
        }

        Window(AppStrings.openSourceLicenses, id: OpenSourceLicensesView.windowID) {
            OpenSourceLicensesView()
        }
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView()
        }
    }
}

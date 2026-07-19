//
//  ApuSeqApp.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import SwiftUI

@main
struct ApuSeqApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ApuSeqDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            FindCommands()
            TranslationCommands()
            ViewPanelCommands()
            ColumnSelectionCommands()
            AlignmentEditCommands()
        }

        Settings {
            AppSettingsView()
        }
    }
}

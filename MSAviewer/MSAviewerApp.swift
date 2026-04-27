//
//  MSAviewerApp.swift
//  MSAviewer
//
//  Created by 須田崚 on 2026/04/27.
//

import SwiftUI

@main
struct MSAviewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MSAviewerDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}

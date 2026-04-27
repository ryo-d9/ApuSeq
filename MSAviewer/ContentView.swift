//
//  ContentView.swift
//  MSAviewer
//
//  Created by 須田崚 on 2026/04/27.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MSAviewerDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(MSAviewerDocument()))
}

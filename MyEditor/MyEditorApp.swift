//
//  MyEditorApp.swift
//  MyEditor
//
//  Created by Rob Evans on 04/07/2026.
//

import SwiftUI

@main
struct MyEditor: App {
    // Shared bridge bindings to pass file commands downward
    @State private var triggerImport = false
    @State private var triggerExport = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                showImporter: $triggerImport,
                showExporter: $triggerExport
            )
        }
        // Native commands live on the WindowGroup Scene, not inside the View
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .saveItem) {
                Button("Open...") { triggerImport = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save As...") { triggerExport = true }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

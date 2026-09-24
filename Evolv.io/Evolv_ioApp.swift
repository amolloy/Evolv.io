//
//  Evolv_ioApp.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree
#if os(macOS)
import AppKit
#endif

@main
struct Evolv_ioApp: App {
    @AppStorage(UserDefaults.supersamplingEnabledKey) private var supersamplingEnabled = true

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Toggle("Supersampling", isOn: $supersamplingEnabled)
                Button("Reload Custom Nodes") {
                    NodeRegistry.shared.reload()
                }
#if os(macOS)
                Button("Reveal Nodes Folder") {
                    if let nodesDirectory = DSLLibrary.containerNodesDirectory {
                        NSWorkspace.shared.activateFileViewerSelecting([nodesDirectory])
                    }
                }
#endif
            }
        }
    }
}

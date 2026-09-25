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

    init() {
        // NodeRegistry.shared is otherwise built lazily on first parse --
        // touch it here so its load log (and any load issues) always show
        // up at launch, not only once something happens to render.
        print("Node registry: \(NodeRegistry.shared.registry.count) node(s) registered")

        // Always on (not just DEBUG) -- Debug builds are too slow to
        // iterate against comfortably even with Metal, so this needs to
        // run against whatever configuration is actually being used.
        Task { await EvolvMCPServer.shared.start() }
    }

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
                Button("Reload Genotypes") {
                    GenotypeStore.shared.reload()
                }
#if os(macOS)
                Button("Reveal Nodes Folder") {
                    if let nodesDirectory = DSLLibrary.containerNodesDirectory {
                        NSWorkspace.shared.activateFileViewerSelecting([nodesDirectory])
                    }
                }
                Button("Reveal Genotypes Folder") {
                    if let genotypesDirectory = GenotypeLibrary.containerGenotypesDirectory {
                        NSWorkspace.shared.activateFileViewerSelecting([genotypesDirectory])
                    }
                }
#endif
            }
        }
    }
}

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
        // The genotype library opens at launch and renders nothing until a
        // genotype is selected.
#if os(macOS)
        Window("Genotype Library", id: Self.genotypeLibraryWindowID) {
            ContentView()
        }
        .defaultLaunchBehavior(.presented)
#endif

        // The 3x3 random grid, from File > New Window. It renders as soon as
        // it opens, so it's kept from opening (or being restored) at launch.
        WindowGroup("Random Grid", id: Self.randomGridWindowID) {
            RandomGridView()
        }
#if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
#endif
        .commands {
#if os(macOS)
            CommandGroup(after: .newItem) {
                OpenGenotypeMenuItem()
            }
#endif
            CommandGroup(after: .appInfo) {
#if os(macOS)
                GenotypeLibraryMenuItem()
#endif
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

    static let genotypeLibraryWindowID = "genotype-library"
    static let randomGridWindowID = "random-grid"
}

#if os(macOS)
/// A menu item needs a View to read `openWindow` from the environment.
private struct GenotypeLibraryMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Genotype Library") {
            openWindow(id: Evolv_ioApp.genotypeLibraryWindowID)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}

/// Opens a genotype file in the focused grid window's full size view.
private struct OpenGenotypeMenuItem: View {
    @FocusedValue(\.openGenotype) private var openGenotype

    var body: some View {
        Button("Open Genotype…") {
            openGenotype?()
        }
        .keyboardShortcut("o")
        .disabled(openGenotype == nil)
    }
}
#endif

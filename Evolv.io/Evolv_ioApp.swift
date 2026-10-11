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
        // Settles iCloud vs. local before anything reads the user Nodes or
        // Genotypes folders (and moves any local files into iCloud).
        print("User library: \(UserLibrary.documentsDirectory?.path ?? "unavailable")")

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

        // A family (see Documentation/EvolutionUI.md), through the standard
        // File > New, Open and Save. Before the genotype window, so File > New
        // makes a family.
        DocumentGroup(newDocument: { FamilyDocument() }) { file in
            FamilyWindowView(document: file.document)
        }
        .commands {
#if os(macOS)
            CommandGroup(after: .newItem) {
                OpenGenotypeMenuItem()
            }
            // After, not replacing, the document Save items families use.
            CommandGroup(after: .saveItem) {
                SaveGenotypeMenuItem()
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

#if os(macOS)
        // A genotype opened with File > Open Genotype.
        WindowGroup("Genotype", id: Self.genotypeWindowID, for: OpenedGenotype.self) { $opened in
            if let opened {
                GenotypeWindowView(opened: opened)
            }
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
#endif
    }

    static let genotypeLibraryWindowID = "genotype-library"
    static let genotypeWindowID = "genotype"
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

/// Opens a genotype file, or an image with a genotype stored in it, in a
/// window of its own.
private struct OpenGenotypeMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Genotype…") {
            GenotypeFilePanels.open { opened in
                openWindow(id: Evolv_ioApp.genotypeWindowID, value: opened)
            }
        }
        // Shift, since Command-O opens a family.
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

/// Saves the genotype in the key full size view. Disabled when no full
/// size view is key.
private struct SaveGenotypeMenuItem: View {
    @FocusedValue(\.saveGenotype) private var saveGenotype

    var body: some View {
        Button("Save Genotype…") {
            saveGenotype?()
        }
        // Option, since Command-S saves a family.
        .keyboardShortcut("s", modifiers: [.command, .option])
        .disabled(saveGenotype == nil)
    }
}
#endif

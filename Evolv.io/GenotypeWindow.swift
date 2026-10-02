//
//  GenotypeWindow.swift
//  Evolv.io
//
//  File > Open Genotype: opens a saved `.evolvgenotype` file, or the
//  genotype stored in an exported image (see ImageExporter.encode), in a
//  window of its own showing it full size. It works whichever window is in
//  front, or with none open, and the genotype isn't added to the genotype
//  library. Also the save panel behind Save as Genotype and File > Save
//  Genotype.
//

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ExpressionTree

/// What a genotype window shows: the value `openWindow` passes it.
struct OpenedGenotype: Codable, Hashable {
	var expression: String
	var name: String?
}

/// A window showing one opened genotype full size.
struct GenotypeWindowView: View {
	let opened: OpenedGenotype

	@State private var genotype: RandomGenotype?
	@State private var errorMessage: String?

	var body: some View {
		Group {
			if let genotype {
				FullSizeGenotypeView(genotype: genotype)
			} else if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
					.padding()
			}
		}
		.navigationTitle(opened.name ?? "Genotype")
		.task(id: opened) {
			do {
				let node = try ContentView.parser.parse(opened.expression)
				genotype = RandomGenotype(text: opened.expression, node: node, name: opened.name)
			} catch {
				errorMessage = "Couldn't parse the expression: \(error.localizedDescription)"
			}
		}
	}
}

/// The open and save panels for genotype files.
enum GenotypeFilePanels {
	/// The type macOS gives `.evolvgenotype` files. The app doesn't declare
	/// one, so this has to be the plain extension-based type: asking for one
	/// that conforms to plain text makes a different type, and the open
	/// panel greys out the files.
	static let genotypeContentType = UTType(filenameExtension: GenotypeLibrary.fileExtension) ?? .data

	/// Asks where to save the expression as an `.evolvgenotype` file, starting
	/// in the user Genotypes folder so it shows up in the genotype library,
	/// but it can go anywhere. The file name becomes the genotype's name.
	@MainActor
	static func save(_ genotype: RandomGenotype) {
		let panel = NSSavePanel()
		panel.title = "Save as Genotype"
		panel.nameFieldStringValue = genotype.name ?? "Untitled"
		panel.allowedContentTypes = [genotypeContentType]
		panel.canCreateDirectories = true
		panel.directoryURL = GenotypeLibrary.containerGenotypesDirectory
		let expression = genotype.text
		run(panel) { url in
			do {
				try GenotypeStore.shared.writeGenotype(expression: expression, to: url)
			} catch {
				NSAlert(error: error).runModal()
			}
		}
	}

	/// Asks for an `.evolvgenotype` file, or an image exported with its
	/// genotype, from anywhere, and passes on what it holds.
	@MainActor
	static func open(_ completion: @escaping (OpenedGenotype) -> Void) {
		let panel = NSOpenPanel()
		panel.title = "Open Genotype"
		panel.allowedContentTypes = [genotypeContentType] + Array(ImageExporter.metadataFormats)
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.directoryURL = GenotypeLibrary.containerGenotypesDirectory
		run(panel) { url in
			do {
				completion(try read(url))
			} catch {
				let alert = NSAlert()
				alert.messageText = "Couldn't open \(url.lastPathComponent)"
				alert.informativeText = (error as? GenotypeParseError)?.message ?? error.localizedDescription
				alert.runModal()
			}
		}
	}

	private static func read(_ url: URL) throws -> OpenedGenotype {
		if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
			guard let embedded = ImageExporter.embeddedGenotype(at: url) else {
				throw OpenImageError()
			}
			return OpenedGenotype(expression: embedded.expression,
								  name: embedded.name ?? url.deletingPathExtension().lastPathComponent)
		}
		let text = try String(contentsOf: url, encoding: .utf8)
		let genotype = try GenotypeLibrary.parse(text, fileURL: url, source: .user).genotype
		// Parse now, so a bad expression is reported here rather than in an
		// empty window.
		_ = try ContentView.parser.parse(genotype.expression)
		return OpenedGenotype(expression: genotype.expression, name: genotype.name ?? genotype.id)
	}

	/// Runs `panel` as a sheet on the key window, or on its own if there's
	/// none, and calls `completion` with the chosen URL.
	@MainActor
	private static func run(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
		let handler: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			completion(url)
		}
		if let window = NSApp.keyWindow {
			panel.beginSheetModal(for: window, completionHandler: handler)
		} else {
			panel.begin(completionHandler: handler)
		}
	}

	private struct OpenImageError: LocalizedError {
		var errorDescription: String? { "This image doesn't have a genotype stored in it. Only images exported from Evolv.io with \"Store genotype in image metadata\" on do." }
	}
}
#endif

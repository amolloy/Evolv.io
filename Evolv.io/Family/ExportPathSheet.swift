//
//  ExportPathSheet.swift
//  Evolv.io
//
//  Export Path…, from a family member's context menu: every genotype on
//  the member's path (it and all its ancestors, both parents' lines for a
//  mated child) rendered with the Export Image options into a folder, one
//  file per genotype, named for its generation. The dialog closes once the
//  folder is chosen and the renders run in the background, with a circular
//  progress in the family window's toolbar (PathExport). macOS only for
//  now, since it writes several files into a folder the user picks.
//

#if os(macOS)
import SwiftUI
import AppKit
import ExpressionTree

struct ExportPathSheet: View {
	/// One genotype on the path.
	struct Item {
		let member: Family.Member
		let generation: Int
	}

	/// Oldest first.
	let items: [Item]
	let defaultBaseName: String
	/// Runs the export once the folder is chosen.
	let export: PathExport

	@Environment(\.dismiss) private var dismiss
	@State private var baseName = ""
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Export Path")
				.font(.headline)
			Text("\(items.count) genotype\(items.count == 1 ? "" : "s"), generation \(items.first?.generation ?? 0) to \(items.last?.generation ?? 0), into a folder you choose next.")
				.foregroundStyle(.secondary)
			Form {
				TextField("Base name", text: $baseName)
				LabeledContent("Files") {
					Text(exampleNames)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
				}
			}
			.formStyle(.columns)
			ExportImageOptions()
			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Export…", action: chooseFolder)
					.keyboardShortcut(.defaultAction)
					.disabled(trimmedBaseName.isEmpty)
			}
		}
		.padding()
		.frame(width: 460)
		.onAppear { if baseName.isEmpty { baseName = defaultBaseName } }
	}

	private var trimmedBaseName: String {
		baseName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
	}

	private var exampleNames: String {
		let names = fileNames(extension: ExportImageSettings.current.format.preferredFilenameExtension ?? "png")
		guard names.count > 3 else { return names.joined(separator: "\n") }
		return [names[0], "…", names[names.count - 1]].joined(separator: "\n")
	}

	/// `Base-gen00.png`, `Base-gen01.png`, ...; a generation with more than
	/// one genotype on the path (a mated child's two parents' lines) adds
	/// the member id, `Base-gen03-g45.png`. Generations are zero-padded so
	/// Finder sorts them in order.
	private func fileNames(extension fileExtension: String) -> [String] {
		Self.fileNames(for: items, baseName: trimmedBaseName, fileExtension: fileExtension)
	}

	static func fileNames(for items: [Item], baseName: String, fileExtension: String) -> [String] {
		let digits = max(2, String(items.map(\.generation).max() ?? 0).count)
		let perGeneration = Dictionary(grouping: items, by: \.generation).mapValues(\.count)
		return items.map { item in
			let generation = String(repeating: "0", count: max(0, digits - String(item.generation).count)) + String(item.generation)
			let suffix = perGeneration[item.generation, default: 1] > 1 ? "-\(item.member.id)" : ""
			return "\(baseName)-gen\(generation)\(suffix).\(fileExtension)"
		}
	}

	private func chooseFolder() {
		errorMessage = nil
		let panel = NSOpenPanel()
		panel.title = "Export Path"
		panel.message = "Choose a folder for the \(items.count) images."
		panel.prompt = "Export"
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.canCreateDirectories = true
		panel.allowsMultipleSelection = false
		let completion: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let folder = panel.url else { return }
			start(into: folder)
		}
		if let window = NSApp.keyWindow {
			panel.beginSheetModal(for: window, completionHandler: completion)
		} else {
			panel.begin(completionHandler: completion)
		}
	}

	/// Checks for files it would replace and that every genotype parses,
	/// then hands the renders to `export` and closes.
	private func start(into folder: URL) {
		let settings = ExportImageSettings.current
		let urls = fileNames(extension: settings.format.preferredFilenameExtension ?? "png")
			.map { folder.appendingPathComponent($0) }

		let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
		if !existing.isEmpty {
			let alert = NSAlert()
			alert.messageText = "Replace \(existing.count) existing file\(existing.count == 1 ? "" : "s")?"
			alert.informativeText = "\(folder.lastPathComponent) already has \(existing.map(\.lastPathComponent).prefix(3).joined(separator: ", "))\(existing.count > 3 ? ", …" : "")."
			alert.addButton(withTitle: "Replace")
			alert.addButton(withTitle: "Cancel")
			guard alert.runModal() == .alertFirstButtonReturn else { return }
		}

		let genotypes: [RandomGenotype]
		do {
			genotypes = try items.map { item in
				do {
					let node = try ContentView.parser.parse(item.member.expression)
					return RandomGenotype(text: item.member.expression, node: node,
										  name: item.member.name ?? "\(trimmedBaseName) generation \(item.generation)")
				} catch {
					throw ImageExporter.ExportError(message: "\(item.member.id) doesn't parse with the nodes loaded now: \(error.localizedDescription)")
				}
			}
		} catch {
			errorMessage = error.localizedDescription
			return
		}

		export.start(genotypes: genotypes, urls: urls, folderName: folder.lastPathComponent, settings: settings)
		dismiss()
	}
}

/// A running Export Path, shown as a circular progress in the family
/// window's toolbar. One at a time per window.
@MainActor
@Observable
final class PathExport {
	private(set) var done = 0
	private(set) var total = 0
	private(set) var folderName = ""
	private(set) var isRunning = false
	/// Set when an export fails or is stopped, for the window to show.
	var errorMessage: String?

	private var task: Task<Void, Never>?

	var fraction: Double {
		total == 0 ? 0 : Double(done) / Double(total)
	}

	func start(genotypes: [RandomGenotype], urls: [URL], folderName: String, settings: ExportImageSettings) {
		guard !isRunning else { return }
		// One band for every image, so a caption below keeps them one size.
		let captionBand = settings.captionBand(for: genotypes)
		done = 0
		total = genotypes.count
		self.folderName = folderName
		isRunning = true
		task = Task {
			var written: [URL] = []
			do {
				for (index, genotype) in genotypes.enumerated() {
					try Task.checkCancellation()
					try await settings.data(for: genotype, captionBand: captionBand).write(to: urls[index], options: .atomic)
					written.append(urls[index])
					done = index + 1
				}
				NSWorkspace.shared.activateFileViewerSelecting(written)
			} catch is CancellationError {
				errorMessage = "Export Path stopped after \(written.count) of \(genotypes.count) images."
			} catch {
				errorMessage = "Export Path stopped after \(written.count) of \(genotypes.count) images: \(error.localizedDescription)"
			}
			isRunning = false
			task = nil
		}
	}

	func stop() {
		task?.cancel()
	}
}
#endif

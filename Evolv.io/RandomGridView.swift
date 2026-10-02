//
//  RandomGridView.swift
//  Evolv.io
//
//  The random grid window (File > New Window): a 3x3 grid of random genotypes from
//  RandomExpressionGenerator (see Documentation/RandomGeneration.md). Each
//  image's context menu shows it full size, in the Debug View or the
//  expression tree viewer, shows or copies its expression, saves it as a
//  genotype file, or exports it as an image (see ImageExport.swift); the full
//  size view's context menu exports it as an image too. The menu works while the image is still rendering. File > Open
//  Genotype shows a saved genotype file full size, and File > Save Genotype
//  saves the one in the key full size view. The genotype library
//  (ContentView) is the window that opens at launch.
//

import SwiftUI
import ExpressionTree
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// One genotype's expression and the node tree parsed from it: generated
/// for the grid, or opened from a file.
struct RandomGenotype: Identifiable {
	let id = UUID()
	let text: String
	let node: any Node
	/// The genotype file's name, for one opened from a file.
	var name: String?
}

struct RandomGridView: View {
	private static let gridSize = 3
	private static let thumbnailSize = CGSize(width: 256, height: 256)

	@AppStorage("randomGridMaxDepth") private var maxDepth = RandomExpressionGenerator.Configuration().maxDepth
	@State private var seed: UInt64 = 0
	@State private var genotypes: [RandomGenotype] = []

	@State private var fullSizeGenotype: RandomGenotype?
	@State private var debugGenotype: RandomGenotype?
	@State private var treeGenotype: RandomGenotype?
	@State private var expressionGenotype: RandomGenotype?
	@State private var savingGenotype: RandomGenotype?
	@State private var exportingGenotype: RandomGenotype?
	/// Export Image… from the full size view, which presents its own sheet
	/// on top of the full size one.
	@State private var exportingFullSizeGenotype: RandomGenotype?

	var body: some View {
		Grid(horizontalSpacing: 12, verticalSpacing: 12) {
			ForEach(0..<Self.gridSize, id: \.self) { row in
				GridRow {
					ForEach(0..<Self.gridSize, id: \.self) { column in
						let index = row * Self.gridSize + column
						if index < genotypes.count {
							cell(for: genotypes[index])
						}
					}
				}
			}
		}
		.padding()
		.navigationTitle("Evolv.io")
#if os(macOS)
		.navigationSubtitle("Seed \(seed)")
#endif
		.toolbar {
			ToolbarItem {
				Stepper("Depth \(maxDepth)", value: $maxDepth, in: 1...20)
					.help("Most levels of function calls in a new genotype")
			}
			ToolbarItem {
				Button("New Genotypes", systemImage: "arrow.clockwise", action: generate)
					.keyboardShortcut("r", modifiers: .command)
					.help("Replace all nine with new random genotypes")
			}
		}
		.onAppear {
			if genotypes.isEmpty { generate() }
		}
		.onChange(of: maxDepth) { generate() }
#if os(macOS)
		.focusedSceneValue(\.openGenotype, openWithPanel)
#endif
		.sheet(item: $fullSizeGenotype) { genotype in
			sheet(title: genotype.name ?? "Full Size", dismiss: { fullSizeGenotype = nil }) {
				VStack(alignment: .leading) {
					RenderedImageView(nodeRenderer: NodeRenderer(node: genotype.node,
																 evaluator: Evaluator(size: CGSize(width: 800, height: 800))))
						.contextMenu {
							Button("Export Image…") { exportingFullSizeGenotype = genotype }
						}
					ExpressionTextView(text: genotype.text)
						.frame(width: 800, height: 120)
				}
				.padding()
			}
			.sheet(item: $exportingFullSizeGenotype) { genotype in
				ExportImageSheet(genotype: genotype)
			}
#if os(macOS)
			// Set inside the sheet so File > Save Genotype follows whichever
			// full size view is key, when several grid windows have one open.
			.focusedSceneValue(\.saveGenotype, { saveWithPanel(genotype) })
#endif
		}
		.sheet(item: $debugGenotype) { genotype in
			sheet(title: "Debug View", dismiss: { debugGenotype = nil }) {
				NodeDebuggingView(evaluator: Evaluator(size: CGSize(width: 512, height: 512)),
								  expressionTree: genotype.node)
					.padding()
			}
#if os(macOS)
			.frame(minWidth: 1000, minHeight: 800)
#endif
		}
		.sheet(item: $treeGenotype) { genotype in
			sheet(title: "Expression Tree", dismiss: { treeGenotype = nil }) {
				TreeVisualizerView(evaluator: Evaluator(size: CGSize(width: 64, height: 64)),
								   rootNode: genotype.node)
			}
#if os(macOS)
			.frame(minWidth: 1000, minHeight: 800)
#endif
			.presentationSizing(.page)
		}
		.sheet(item: $expressionGenotype) { genotype in
			sheet(title: "Expression", dismiss: { expressionGenotype = nil }) {
				ExpressionTextView(text: genotype.text)
					.frame(minWidth: 400, idealWidth: 600, minHeight: 120, idealHeight: 240)
					.padding()
			}
		}
		.sheet(item: $savingGenotype) { genotype in
			SaveGenotypeSheet(expression: genotype.text)
		}
		.sheet(item: $exportingGenotype) { genotype in
			ExportImageSheet(genotype: genotype)
		}
	}

	private func cell(for genotype: RandomGenotype) -> some View {
		RenderedImageView(nodeRenderer: NodeRenderer(node: genotype.node,
													 evaluator: Evaluator(size: Self.thumbnailSize)))
			.frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
			.clipShape(RoundedRectangle(cornerRadius: 8))
			// The whole cell, not just the spinner, takes clicks while it's
			// still rendering.
			.contentShape(RoundedRectangle(cornerRadius: 8))
			.id(genotype.id)
			.help(genotype.text)
			.onTapGesture(count: 2) { fullSizeGenotype = genotype }
			.contextMenu {
				Button("Show Full Size") { fullSizeGenotype = genotype }
				Button("Show Debug View") { debugGenotype = genotype }
				Button("Show Expression Tree") { treeGenotype = genotype }
				Button("Show Expression…") { expressionGenotype = genotype }
				Divider()
#if os(macOS)
				Button("Save as Genotype…") { saveWithPanel(genotype) }
				Button("Copy Expression") {
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(genotype.text, forType: .string)
				}
#else
				Button("Save as Genotype…") { savingGenotype = genotype }
#endif
				Button("Export Image…") { exportingGenotype = genotype }
			}
	}

	private func sheet<Content: View>(title: String, dismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
		NavigationStack {
			content()
				.navigationTitle(title)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Done", action: dismiss)
					}
				}
		}
	}

#if os(macOS)
	/// The type macOS gives `.evolvgenotype` files. The app doesn't declare
	/// one, so this has to be the plain extension-based type: asking for one
	/// that conforms to plain text makes a different type, and the open
	/// panel greys out the files.
	private static let genotypeContentType = UTType(filenameExtension: GenotypeLibrary.fileExtension) ?? .data

	/// Asks where to save the expression as an `.evolvgenotype` file, starting
	/// in the user Genotypes folder so it shows up in the genotype library,
	/// but it can go anywhere. The file name becomes the genotype's name.
	private func saveWithPanel(_ genotype: RandomGenotype) {
		let panel = NSSavePanel()
		panel.title = "Save as Genotype"
		panel.nameFieldStringValue = genotype.name ?? "Untitled"
		panel.allowedContentTypes = [Self.genotypeContentType]
		panel.canCreateDirectories = true
		panel.directoryURL = GenotypeLibrary.containerGenotypesDirectory
		let expression = genotype.text
		let completion: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			do {
				try GenotypeStore.shared.writeGenotype(expression: expression, to: url)
			} catch {
				NSAlert(error: error).runModal()
			}
		}
		if let window = NSApp.keyWindow {
			panel.beginSheetModal(for: window, completionHandler: completion)
		} else {
			panel.begin(completionHandler: completion)
		}
	}

	/// Asks for an `.evolvgenotype` file, from anywhere, and shows it full
	/// size. It isn't added to the genotype library.
	private func openWithPanel() {
		let panel = NSOpenPanel()
		panel.title = "Open Genotype"
		panel.allowedContentTypes = [Self.genotypeContentType]
		panel.allowsMultipleSelection = false
		panel.canChooseDirectories = false
		panel.directoryURL = GenotypeLibrary.containerGenotypesDirectory
		let completion: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .OK, let url = panel.url else { return }
			do {
				let text = try String(contentsOf: url, encoding: .utf8)
				let genotype = try GenotypeLibrary.parse(text, fileURL: url, source: .user).genotype
				let node = try ContentView.parser.parse(genotype.expression)
				fullSizeGenotype = RandomGenotype(text: genotype.expression, node: node, name: genotype.name ?? genotype.id)
			} catch {
				let alert = NSAlert()
				alert.messageText = "Couldn't open \(url.lastPathComponent)"
				alert.informativeText = (error as? GenotypeParseError)?.message ?? error.localizedDescription
				alert.runModal()
			}
		}
		if let window = NSApp.keyWindow {
			panel.beginSheetModal(for: window, completionHandler: completion)
		} else {
			panel.begin(completionHandler: completion)
		}
	}
#endif

	/// Nine new genotypes from a fresh seed. The seed is shown in the window
	/// subtitle, so a grid can be regenerated from it later.
	private func generate() {
		seed = UInt64.random(in: 0...UInt64.max)
		var rng = SeededRandomNumberGenerator(seed: seed)
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.maxDepth = maxDepth
		configuration.excludedRootFunctions = UserDefaults.standard.randomExcludedRootNodes
		configuration.excludedVariables = UserDefaults.standard.randomExcludedVariables
		let generator = RandomExpressionGenerator(signatures: NodeRegistry.shared.signatures, configuration: configuration)
		genotypes = (0..<(Self.gridSize * Self.gridSize)).map { _ in
			let expression = generator.generate(using: &rng)
			let node: any Node
			do {
				node = try ContentView.parser.parse(expression.description)
			} catch {
				// Shouldn't happen: the generator only uses registered nodes
				// with their declared arity.
				print("Generated expression doesn't parse: \(expression) -- \(error.localizedDescription)")
				node = Constant(0)
			}
			return RandomGenotype(text: expression.description, node: node)
		}
	}
}

/// The expression in the full size and Show Expression sheets: read-only, but selectable and
/// copyable, and scrolls when it's long.
private struct ExpressionTextView: View {
	let text: String

	var body: some View {
#if os(macOS)
		SelectableTextView(text: text)
			.overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
#else
		ScrollView {
			Text(text)
				.font(.system(.body, design: .monospaced))
				.textSelection(.enabled)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
#endif
	}
}

#if os(macOS)
/// File > Open Genotype, published by the focused RandomGridView.
struct OpenGenotypeKey: FocusedValueKey {
	typealias Value = () -> Void
}

/// File > Save Genotype, published by the key full size view.
struct SaveGenotypeKey: FocusedValueKey {
	typealias Value = () -> Void
}

extension FocusedValues {
	var openGenotype: OpenGenotypeKey.Value? {
		get { self[OpenGenotypeKey.self] }
		set { self[OpenGenotypeKey.self] = newValue }
	}

	var saveGenotype: SaveGenotypeKey.Value? {
		get { self[SaveGenotypeKey.self] }
		set { self[SaveGenotypeKey.self] = newValue }
	}
}

/// A non-editable NSTextView: any part of the expression can be selected and
/// copied, with the usual Copy and Select All menu items.
private struct SelectableTextView: NSViewRepresentable {
	let text: String

	func makeNSView(context: Context) -> NSScrollView {
		let scrollView = NSTextView.scrollableTextView()
		let textView = scrollView.documentView as! NSTextView
		textView.isEditable = false
		textView.isSelectable = true
		textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
		textView.textContainerInset = NSSize(width: 4, height: 4)
		return scrollView
	}

	func updateNSView(_ scrollView: NSScrollView, context: Context) {
		let textView = scrollView.documentView as! NSTextView
		if textView.string != text {
			textView.string = text
		}
	}
}
#endif

/// Asks for a name and saves the expression as a user genotype (see
/// GenotypeStore.saveUserGenotype). It then shows up in the genotype
/// library window.
/// Used where there's no save panel; on macOS, see saveWithPanel.
private struct SaveGenotypeSheet: View {
	let expression: String

	@Environment(\.dismiss) private var dismiss
	@State private var name = ""
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Save as Genotype")
				.font(.headline)
			TextField("Name", text: $name)
				.textFieldStyle(.roundedBorder)
				.onSubmit(save)
			Text(expression)
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
				.lineLimit(4)
				.textSelection(.enabled)
			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Save", action: save)
					.keyboardShortcut(.defaultAction)
					.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.padding()
		.frame(width: 420)
	}

	private func save() {
		do {
			try GenotypeStore.shared.saveUserGenotype(name: name, expression: expression)
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}

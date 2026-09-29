//
//  RandomGridView.swift
//  Evolv.io
//
//  The main window: a 3x3 grid of random genotypes from
//  RandomExpressionGenerator (see Documentation/RandomGeneration.md). Each
//  image's context menu shows it full size, in the Debug View or the
//  expression tree viewer, or saves it as a user genotype. The genotype
//  library (ContentView) is in its own window, from the app menu.
//

import SwiftUI
import ExpressionTree
#if os(macOS)
import AppKit
#endif

/// One generated genotype and the node tree parsed from it.
struct RandomGenotype: Identifiable {
	let id = UUID()
	let expression: GeneratedExpression
	let node: any Node

	var text: String { expression.description }
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
	@State private var savingGenotype: RandomGenotype?

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
		.sheet(item: $fullSizeGenotype) { genotype in
			sheet(title: "Full Size", dismiss: { fullSizeGenotype = nil }) {
				VStack(alignment: .leading) {
					RenderedImageView(nodeRenderer: NodeRenderer(node: genotype.node,
																 evaluator: Evaluator(size: CGSize(width: 800, height: 800))))
					Text(genotype.text)
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: 800, alignment: .leading)
				}
				.padding()
			}
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
		.sheet(item: $savingGenotype) { genotype in
			SaveGenotypeSheet(expression: genotype.text)
		}
	}

	private func cell(for genotype: RandomGenotype) -> some View {
		RenderedImageView(nodeRenderer: NodeRenderer(node: genotype.node,
													 evaluator: Evaluator(size: Self.thumbnailSize)))
			.frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.id(genotype.id)
			.help(genotype.text)
			.onTapGesture(count: 2) { fullSizeGenotype = genotype }
			.contextMenu {
				Button("Show Full Size") { fullSizeGenotype = genotype }
				Button("Show Debug View") { debugGenotype = genotype }
				Button("Show Expression Tree") { treeGenotype = genotype }
				Divider()
				Button("Save as Genotype…") { savingGenotype = genotype }
#if os(macOS)
				Button("Copy Expression") {
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(genotype.text, forType: .string)
				}
#endif
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

	/// Nine new genotypes from a fresh seed. The seed is shown in the window
	/// subtitle, so a grid can be regenerated from it later.
	private func generate() {
		seed = UInt64.random(in: 0...UInt64.max)
		var rng = SeededRandomNumberGenerator(seed: seed)
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.maxDepth = maxDepth
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
			return RandomGenotype(expression: expression, node: node)
		}
	}
}

/// Asks for a name and saves the expression as a user genotype (see
/// GenotypeStore.saveUserGenotype). It then shows up in the genotype
/// library window.
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

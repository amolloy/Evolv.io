//
//  ContentView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

struct ContentView: View {
	static let parser = Parser()

	private let store = GenotypeStore.shared

	@State private var selectedID: String? = nil
	@State private var showingTreeVisualizer = false
	@State private var showingDebugView = false
	@State private var exportingGenotype: RandomGenotype?

	var body: some View {
		NavigationSplitView {
			GenotypeSidebar(selectedID: $selectedID)
			.frame(minWidth: 200)
			.onChange(of: selectedID, initial: true) { _, newValue in
				MCPLiveUIState.selectedGenotypeID = newValue
			}
		} detail: {
			if let selectedID, let genotype = store.genotype(id: selectedID) {
				let node = node(for: genotype.expression)
				let nodeRenderer = NodeRenderer(node: node,
												 evaluator: Evaluator(size: CGSize(width: 800, height: 800)))
				RenderedImageView(nodeRenderer: nodeRenderer)
				.id(genotype)
				.contextMenu {
					Button("Copy Image") {
						nodeRenderer.copyImageToPasteboard()
					}
					Button("Export Image…") {
						exportingGenotype = RandomGenotype(text: genotype.expression, node: node, name: genotype.displayName)
					}
					Button("Show Expression Tree") {
						showingTreeVisualizer = true
					}
					Button("Show Debug View") {
						showingDebugView = true
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: 12))
				.shadow(radius: 5)
				.navigationTitle(genotype.displayName)
				.sheet(item: $exportingGenotype) { genotype in
					ExportImageSheet(genotype: genotype)
				}
				.sheet(isPresented: $showingTreeVisualizer) {
					NavigationStack {
						TreeVisualizerView(evaluator: Evaluator(size: CGSize(width: 64, height: 64)),
										   rootNode: node)
							.toolbar {
								ToolbarItem(placement: .cancellationAction) {
									Button("Done") {
										showingTreeVisualizer = false
									}
								}
							}
					}
#if os(macOS)
					.frame(minWidth: 1000, minHeight: 800)
#endif
					.presentationSizing(.page)
				}
				.sheet(isPresented: $showingDebugView) {
					NavigationStack {
						NodeDebuggingView(evaluator: Evaluator(size: CGSize(width: 512, height: 512)),
										   expressionTree: node,
										   originalImageURL: genotype.originalImageURL)
							.padding()
							.toolbar {
								ToolbarItem(placement: .cancellationAction) {
									Button("Done") {
										showingDebugView = false
									}
								}
							}
					}
#if os(macOS)
					.frame(minWidth: 1000, minHeight: 800)
#endif
				}
			} else {
				Text("Select a genotype")
			}
		}
	}

	func node(for expression: String) -> any Node {
		do {
			return try ContentView.parser.parse(expression)
		} catch let e {
			print("Error parsing expression \"\(expression)\": \(e.localizedDescription)")
			return Constant(0)
		}
	}
}

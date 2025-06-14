//
//  NodeTreeView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import SwiftUI
import ExpressionTree

final class DisplayNode: Identifiable {
	let id: ObjectIdentifier
	let node: any Node
	var children: [DisplayNode]?

	init(node: any Node) {
		self.id = node.id
		self.node = node
		if !node.children.isEmpty {
			self.children = node.children.map { DisplayNode(node: $0) }
		}
	}
}

struct TreeVisualizerView: View {
	let evaluator: Evaluator
	let rootNodes: [DisplayNode]

	@State private var selectedNodeForDetail: DisplayNode?

	init(evaluator: Evaluator, rootNode: any Node) {
		self.evaluator = evaluator
		self.rootNodes = [DisplayNode(node: rootNode)]
	}

	var body: some View {
		List(rootNodes, children: \.children) { displayNode in
			Button(action: {
				selectedNodeForDetail = displayNode
			}) {
				NodeRowView(evaluator: evaluator,
							node: displayNode.node)
			}
			.buttonStyle(.plain)
		}
		.navigationTitle("Expression Tree")
		.sheet(item: $selectedNodeForDetail) { displayNodeToShow in
			DetailImageView(node: displayNodeToShow.node)
		}
	}
}

struct NodeRowView: View {
	let evaluator: Evaluator
	let node: any Node

	var body: some View {
		HStack {
			Text(type(of: node).name)
				.font(.caption.bold())
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.background(Color.blue.opacity(0.2), in: Capsule())

			Text(node.toString())
				.font(.caption.monospaced())
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer()

			RenderedImageView(evaluator: Evaluator(size: CGSize(width: 44, height: 44)),
							  expressionTree: node)
		}
		.padding(.vertical, 2)
	}
}

struct DetailImageView: View {
	let node: any Node

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 20) {
			Text("Detail View")
				.font(.headline)

			Text(node.toString())
				.font(.caption.monospaced())
				.padding(.horizontal)
				.textSelection(.enabled)

			NodeDebuggingView(
				evaluator: Evaluator(size: CGSize(width: 512, height: 512)),
				expressionTree: node
			)
			.clipShape(RoundedRectangle(cornerRadius: 16))
			.shadow(radius: 10)

			Button("Done") {
				dismiss()
			}
			.keyboardShortcut(.defaultAction)

		}
		.padding()
		.frame(minWidth: 600, minHeight: 700)
	}
}

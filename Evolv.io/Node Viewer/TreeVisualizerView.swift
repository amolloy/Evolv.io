//
//  TreeVisualizerView.swift
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
				NodeRowView(nodeRenderer: NodeRenderer(node: displayNode.node,
													   evaluator: evaluator))
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
	let nodeRenderer: NodeRenderer

	var body: some View {
		HStack {
			Text(type(of: nodeRenderer.node).name)
				.font(.caption.bold())
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.background(Color.blue.opacity(0.2), in: Capsule())

			Text(nodeRenderer.node.toString())
				.font(.caption.monospaced())
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer()

			RenderedImageView(nodeRenderer: nodeRenderer)
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

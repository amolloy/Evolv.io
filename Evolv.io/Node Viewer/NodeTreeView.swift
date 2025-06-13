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

	init(evaluator: Evaluator, rootNode: any Node) {
		self.evaluator = evaluator
		self.rootNodes = [DisplayNode(node: rootNode)]
	}

	var body: some View {
		List(rootNodes, children: \.children) { displayNode in
			NodeRowView(evaluator: evaluator,
						node: displayNode.node)
		}
		//.listStyle(.insetGrouped)
		.navigationTitle("Expression Tree")
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

			RenderedImageView(evaluator: evaluator,
							  expressionTree: node)
		}
		.padding(.vertical, 2)
	}
}

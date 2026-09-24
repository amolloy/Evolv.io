//
//  TreeVisualizerView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import SwiftUI
import ExpressionTree

struct TreeVisualizerView: View {
	let evaluator: Evaluator
	let rootNode: any Node
	let layout: TreeLayout

	@State private var store = TreeThumbnailStore()
	@State private var selectedNodeForDetail: LaidOutNode?

	init(evaluator: Evaluator, rootNode: any Node) {
		self.evaluator = evaluator
		self.rootNode = rootNode
		self.layout = TreeLayout(rootNode: rootNode)
	}

	var body: some View {
		ScrollView([.horizontal, .vertical]) {
			ZStack(alignment: .topLeading) {
				Canvas { context, _ in
					// Anchor each edge to the tile's top/bottom edge rather than its
					// center, so the line stays within the empty gap between tiers
					// and never runs underneath a tile's thumbnail or badge.
					for laidOut in layout.nodes {
						guard let parentCenter = laidOut.parentCenter else { continue }
						let parentEdge = CGPoint(x: parentCenter.x, y: parentCenter.y + TreeLayout.tileSize.height / 2)
						let childEdge = CGPoint(x: laidOut.center.x, y: laidOut.center.y - TreeLayout.tileSize.height / 2)
						let midY = (parentEdge.y + childEdge.y) / 2

						var path = Path()
						path.move(to: parentEdge)
						path.addLine(to: CGPoint(x: parentEdge.x, y: midY))
						path.addLine(to: CGPoint(x: childEdge.x, y: midY))
						path.addLine(to: childEdge)

						context.stroke(path, with: .color(.secondary), lineWidth: 1.5)
					}
				}
				.frame(width: layout.contentSize.width, height: layout.contentSize.height)

				ForEach(layout.nodes) { laidOut in
					Button {
						selectedNodeForDetail = laidOut
					} label: {
						NodeTileView(node: laidOut.node, image: store.images[laidOut.node.toString()])
					}
					.buttonStyle(.plain)
					.position(laidOut.center)
				}
			}
			.frame(width: layout.contentSize.width, height: layout.contentSize.height)
			.padding(24)
		}
		.navigationTitle("Expression Tree")
		.task {
			await store.renderAll(nodes: layout.nodes, evaluator: evaluator)
		}
		.sheet(item: $selectedNodeForDetail) { laidOut in
			DetailImageView(node: laidOut.node)
		}
	}
}

private struct NodeTileView: View {
	let node: any Node
	let image: CGImage?

	var body: some View {
		VStack(spacing: 4) {
			Group {
				if let image {
					Image(decorative: image, scale: 1.0, orientation: .up)
						.resizable()
				} else {
					Rectangle()
						.fill(Color.secondary.opacity(0.15))
				}
			}
			.frame(width: TreeLayout.tileSize.width, height: TreeLayout.tileSize.width)
			.clipShape(RoundedRectangle(cornerRadius: 6))

			Text(type(of: node).name)
				.font(.caption.bold())
				.lineLimit(1)
				.padding(.horizontal, 8)
				.padding(.vertical, 3)
				.background {
					// Two opaque layers, not one translucent one: `.background`
					// gives a fully opaque base (so nothing -- like a connector
					// line -- can ever show through), with the blue tint layered
					// on top for the same light-wash look as before.
					Capsule()
						.fill(.background)
						.overlay(Capsule().fill(Color.blue.opacity(0.2)))
				}
		}
		.frame(width: TreeLayout.tileSize.width, height: TreeLayout.tileSize.height)
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

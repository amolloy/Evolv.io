//
//  NodeDebuggingView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/13/25.
//

import SwiftUI
import ExpressionTree

struct NodeDebuggingView: View {
	let evaluator: Evaluator
	let expressionTree: any Node
	let nodeRenderer: NodeRenderer
	@State private var image: CGImage?

	init(evaluator: Evaluator,
		 expressionTree: any Node) {
		self.evaluator = evaluator
		self.expressionTree = expressionTree

		self.nodeRenderer = NodeRenderer(node: expressionTree,
										 evaluator: evaluator)
	}

	var body: some View {
		Group {
			if let image = image {
				VStack {
					Image(decorative: image, scale: 1.0, orientation: .up)
						.frame(width: evaluator.size.width, height: evaluator.size.height)
					
				}
			} else {
				ProgressView("Rendering...")
			}
		}
		.task {
			await nodeRenderer.render()
			image = nodeRenderer.cgImage()
		}
	}
}

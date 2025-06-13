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
	@State private var image: CGImage?

	var body: some View {
		Group {
			if let image = image {
				Image(decorative: image, scale: 1.0, orientation: .up)
					.frame(width: evaluator.size.width, height: evaluator.size.height)
			} else {
				ProgressView("Rendering...")
			}
		}
		.task {
			let nodeRenderer = NodeRenderer(node: expressionTree,
											evaluator: evaluator)
			await nodeRenderer.render()
			image = nodeRenderer.cgImage()
		}
	}
}

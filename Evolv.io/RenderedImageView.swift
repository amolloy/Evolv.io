//
//  RenderedImageView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

struct RenderedImageView: View {
	let nodeRenderer: NodeRenderer
	@State private var image: CGImage?

	var body: some View {
		Group {
			if let image = image {
				Image(decorative: image, scale: 1.0, orientation: .up)
					.frame(width: nodeRenderer.evaluator.size.width,
						   height: nodeRenderer.evaluator.size.height)
			} else {
				ProgressView("Rendering...")
			}
		}
		.task {
			image = nil
			await nodeRenderer.render()
			image = nodeRenderer.cgImage()
		}
	}
}

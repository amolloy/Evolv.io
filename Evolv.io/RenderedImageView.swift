//
//  RenderedImageView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI
import ExpressionTree

struct RenderedImageView: View {
	let expressionTree: Tree
	@State private var image: CGImage?

	var body: some View {
		Group {
			if let image = image {
				Image(decorative: image, scale: 1.0, orientation: .up)
					.resizable()
					.scaledToFit()
			} else {
				ProgressView("Rendering...")
			}
		}
		.task {
			let pixelBuffer = expressionTree.evaluate()
			image = pixelBuffer.makeCGImage()
		}
	}
}

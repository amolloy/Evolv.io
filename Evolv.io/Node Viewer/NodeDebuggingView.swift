//
//  NodeDebuggingView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/13/25.
//

import SwiftUI
import ExpressionTree

struct NodeDebuggingView: View {
	@StateObject private var nodeRenderer: NodeRenderer
	@State private var image: CGImage?

	init(evaluator: Evaluator, expressionTree: any Node) {
		self._nodeRenderer = StateObject(wrappedValue: NodeRenderer(node: expressionTree,
																	evaluator: evaluator))
	}

	var body: some View {
		VStack(spacing: 20) {
			if let image = image {
				Image(decorative: image, scale: 1.0, orientation: .up)
					.resizable()
					.interpolation(.none)
					.aspectRatio(1, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.shadow(radius: 5)
			} else {
				ProgressView("Rendering...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}

			VStack {
				RangeSliderView(label: "Red",
								value: redBinding(),
								in: -2...2)

				RangeSliderView(label: "Green",
								value: greenBinding(),
								in: -2...2)

				RangeSliderView(label: "Blue",
								value: blueBinding(),
								in: -2...2)
			}
			.padding()
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

		}
		.padding()
		.task {
			await nodeRenderer.render()
			image = nodeRenderer.cgImage()
		}
		.onChange(of: nodeRenderer.displayMin) { _, _ in updateImage() }
		.onChange(of: nodeRenderer.displayMax) { _, _ in updateImage() }
	}

	private func updateImage() {
		image = nodeRenderer.cgImage()
	}

	private func redBinding() -> Binding<ClosedRange<ComponentType>> {
		Binding {
			nodeRenderer.displayMin.x...nodeRenderer.displayMax.x
		} set: { newRange in
			nodeRenderer.displayMin.x = newRange.lowerBound
			nodeRenderer.displayMax.x = newRange.upperBound
		}
	}

	private func greenBinding() -> Binding<ClosedRange<ComponentType>> {
		Binding {
			nodeRenderer.displayMin.y...nodeRenderer.displayMax.y
		} set: { newRange in
			nodeRenderer.displayMin.y = newRange.lowerBound
			nodeRenderer.displayMax.y = newRange.upperBound
		}
	}

	private func blueBinding() -> Binding<ClosedRange<ComponentType>> {
		Binding {
			nodeRenderer.displayMin.z...nodeRenderer.displayMax.z
		} set: { newRange in
			nodeRenderer.displayMin.z = newRange.lowerBound
			nodeRenderer.displayMax.z = newRange.upperBound
		}
	}
}

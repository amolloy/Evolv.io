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
					.contextMenu {
						// --- Step 2: Add a "Copy" Button ---
						Button {
							copyImageToPasteboard(image)
						} label: {
							Label("Copy Image", systemImage: "doc.on.doc")
						}
					}
				VStack {
					RangeSliderView(label: "Red",
									value: redBinding(),
									in: nodeRenderer.minValue.x...nodeRenderer.maxValue.x)

					RangeSliderView(label: "Green",
									value: greenBinding(),
									in: nodeRenderer.minValue.y...nodeRenderer.maxValue.y)

					RangeSliderView(label: "Blue",
									value: blueBinding(),
									in: nodeRenderer.minValue.z...nodeRenderer.maxValue.z)
				}
				.padding()
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
			} else {
				ProgressView("Rendering...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
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

	private func copyImageToPasteboard(_ image: CGImage) {
#if canImport(AppKit)
		guard let pngData = image.pngData() else {
			print("Failed to convert CGImage to PNG data.")
			return
		}

		// 1. Get the general system pasteboard.
		let pasteboard = NSPasteboard.general

		// 2. Clear its previous contents.
		pasteboard.clearContents()

		// 3. Write the new PNG data to the pasteboard.
		if pasteboard.setData(pngData, forType: .png) {
			print("Image copied to pasteboard.")
		} else {
			print("Failed to write image to pasteboard.")
		}
#endif
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

fileprivate extension CGImage {
	func pngData() -> Data? {
		guard let mutableData = CFDataCreateMutable(nil, 0) else { return nil }
		guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, self, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return mutableData as Data
	}
}

//
//  ColorGradientDebugView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 9/1/26.
//

import SwiftUI
import ExpressionTree

// Temporary test rig for tuning ColorGradient's hardcoded delta/heightFactor/lightZ
// constants live against any figure, without waiting on full-resolution renders.
// Back this out (along with the ColorGradient.debug* statics) once done experimenting.
struct ColorGradientDebugView: View {
	private static let previewSize = CGSize(width: 200, height: 200)
	private static let fullSize = CGSize(width: 800, height: 800)

	private let parser = Parser()

	@State private var selectedFigure: String
	@State private var delta: Double = Double(ColorGradient.debugDelta)
	@State private var heightFactor: Double = Double(ColorGradient.debugHeightFactor)
	@State private var lightZ: Double = Double(ColorGradient.debugLightZ)
	@State private var sharedNormal: Bool = ColorGradient.debugSharedNormal


	@State private var previewRenderer: NodeRenderer?
	@State private var previewImage: CGImage?
	@State private var renderGeneration = 0

	@State private var fullResRenderer: NodeRenderer?
	@State private var fullResImage: CGImage?
	@State private var isRenderingFullRes = false

	init() {
		_selectedFigure = State(initialValue: ContentView.sampleExpressions["Figure 9"] != nil ? "Figure 9" : (ContentView.sampleExpressions.keys.sorted().first ?? ""))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Picker("Figure", selection: $selectedFigure) {
				ForEach(ContentView.sampleExpressions.keys.sorted(), id: \.self) { key in
					Text(key).tag(key)
				}
			}
			.pickerStyle(.menu)

			Group {
				if let previewImage {
					Image(decorative: previewImage, scale: 1.0, orientation: .up)
						.resizable()
						.scaledToFit()
						.frame(width: Self.fullSize.width, height: Self.fullSize.height)
						.contextMenu {
							Button("Copy Image") {
								previewRenderer?.copyImageToPasteboard()
							}
						}
				} else {
					ProgressView("Rendering...")
						.frame(width: Self.previewSize.width, height: Self.previewSize.height)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 12))
			.shadow(radius: 5)

			VStack(alignment: .leading, spacing: 12) {
				debugSlider(label: "delta", value: $delta, range: 0...0.25)
				debugSlider(label: "heightFactor", value: $heightFactor, range: 0.1...200)
				debugSlider(label: "lightZ", value: $lightZ, range: 0...10)
				Toggle("shared normal (collapse channels)", isOn: $sharedNormal)
			}

			Button(isRenderingFullRes ? "Rendering full res..." : "Render Full Resolution") {
				renderFullRes()
			}
			.disabled(isRenderingFullRes)

			if let fullResImage {
				Image(decorative: fullResImage, scale: 1.0, orientation: .up)
					.interpolation(.none)
					.resizable()
					.scaledToFit()
					.frame(maxWidth: 360, maxHeight: 360)
					.contextMenu {
						Button("Copy Image") {
							fullResRenderer?.copyImageToPasteboard()
						}
					}
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.shadow(radius: 5)
			}
		}
		.padding()
		.frame(minWidth: 280)
		.onChange(of: selectedFigure) { _, _ in renderPreview() }
		.onChange(of: delta) { _, newValue in
			ColorGradient.debugDelta = ComponentType(newValue)
			renderPreview()
		}
		.onChange(of: heightFactor) { _, newValue in
			ColorGradient.debugHeightFactor = ComponentType(newValue)
			renderPreview()
		}
		.onChange(of: lightZ) { _, newValue in
			ColorGradient.debugLightZ = ComponentType(newValue)
			renderPreview()
		}
		.onChange(of: sharedNormal) { _, newValue in
			ColorGradient.debugSharedNormal = newValue
			renderPreview()
		}
		.task {
			renderPreview()
		}
	}

	private func debugSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
		HStack {
			Text(label)
				.font(.caption.bold())
				.frame(width: 90, alignment: .leading)
			Slider(value: value, in: range)
			Text(String(format: "%.4f", value.wrappedValue))
				.font(.caption.monospacedDigit())
				.frame(width: 60, alignment: .trailing)
		}
	}

	private func node(for figure: String) -> any Node {
		guard let expression = ContentView.sampleExpressions[figure] else {
			return Constant(0)
		}
		do {
			return try parser.parse(expression)
		} catch {
			print("Error parsing expression:", expression)
			return Constant(0)
		}
	}

	private func renderPreview() {
		renderGeneration += 1
		let generation = renderGeneration
		let renderer = NodeRenderer(node: node(for: selectedFigure),
									 evaluator: Evaluator(size: Self.previewSize))
		previewRenderer = renderer
		Task {
			await renderer.render()
			guard generation == renderGeneration else { return }
			previewImage = renderer.cgImage()
		}
	}

	private func renderFullRes() {
		isRenderingFullRes = true
		let renderer = NodeRenderer(node: node(for: selectedFigure),
									 evaluator: Evaluator(size: Self.fullSize))
		fullResRenderer = renderer
		Task {
			await renderer.render()
			fullResImage = renderer.cgImage()
			isRenderingFullRes = false
		}
	}
}

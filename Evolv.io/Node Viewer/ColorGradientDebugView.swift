//
//  ColorGradientDebugView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 9/1/26.
//

import SwiftUI
import ExpressionTree

// Temporary test rig for tuning ColorGradient's hardcoded delta/heightFactor/lightZ
// Back this out (along with the ColorGradient.debug* statics) once done experimenting.
struct ColorGradientDebugView: View {
	private static let size = CGSize(width: 800, height: 800)

	private let parser = Parser()

	@State private var selectedFigure: String
	@State private var delta: Double = Double(ColorGradient.debugDelta)
	@State private var heightFactor: Double = Double(ColorGradient.debugHeightFactor)
	@State private var lightZ: Double = Double(ColorGradient.debugLightZ)
	@State private var tapCount: Double = Double(ColorGradient.debugTapCount)

	@State private var previewRenderer: NodeRenderer?
	@State private var previewImage: CGImage?
	@State private var renderGeneration = 0

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
						.frame(width: Self.size.width, height: Self.size.height)
						.contextMenu {
							Button("Copy Image") {
								previewRenderer?.copyImageToPasteboard()
							}
						}
				} else {
					ProgressView("Rendering...")
						.frame(width: Self.size.width, height: Self.size.height)
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: 12))
			.shadow(radius: 5)

			VStack(alignment: .leading, spacing: 12) {
				debugSlider(label: "delta", value: $delta, range: 0...0.25)
				debugSlider(label: "heightFactor", value: $heightFactor, range: 0.1...200)
				debugSlider(label: "lightZ", value: $lightZ, range: 0...10)
				debugSlider(label: "tapCount", value: $tapCount, range: 1...16, step: 1)
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
		.onChange(of: tapCount) { _, newValue in
			ColorGradient.debugTapCount = Int(newValue)
			renderPreview()
		}
		.task {
			renderPreview()
		}
	}

	private func debugSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0) -> some View {
		HStack {
			Text(label)
				.font(.caption.bold())
				.frame(width: 90, alignment: .leading)
			if step > 0 {
				Slider(value: value, in: range, step: step)
			} else {
				Slider(value: value, in: range)
			}
			Text(step > 0 ? String(format: "%.0f", value.wrappedValue) : String(format: "%.4f", value.wrappedValue))
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
									 evaluator: Evaluator(size: Self.size))
		previewRenderer = renderer
		Task {
			await renderer.render()
			guard generation == renderGeneration else { return }
			previewImage = renderer.cgImage()
		}
	}
}

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

	@State private var hoverLocation: CGPoint?
	@State private var debugInfo: [String: String] = [:]

	init(evaluator: Evaluator, expressionTree: any Node) {
		self._nodeRenderer = StateObject(wrappedValue: NodeRenderer(node: expressionTree,
																	evaluator: evaluator))
	}

	var body: some View {
		VStack(spacing: 20) {
			if let image = image {
				GeometryReader { imageGeometry in
					Image(decorative: image, scale: 1.0, orientation: .up)
						.interpolation(.none)
						.contentShape(Rectangle())
						.gesture(
							DragGesture(minimumDistance: 0)
								.onChanged { value in
									updateDebugInfo(for: value.location, in: imageGeometry.size)
								}
						)
						.overlay {
							if let hoverLocation = hoverLocation, !debugInfo.isEmpty {
								DebugPopoverView(
									debugInfo: debugInfo,
									hoverLocation: hoverLocation,
									containerSize: imageGeometry.size
								)
								.gesture(DragGesture().onEnded { _ in self.hoverLocation = nil })
							}
						}
						.contextMenu {
							Button("Copy Image") {
								nodeRenderer.copyImageToPasteboard()
							}
						}
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.shadow(radius: 5)
				}
				.aspectRatio(1, contentMode: .fit) // Constrain the GeometryReader to the image's aspect ratio

				// The range sliders Vstack
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

				// Live toggle/slider controls any DSL node in this tree
				// declared via `debug slider(...)`/`debug toggle` -- see
				// LiveDebugValues. Nil until the first render completes, and
				// stays nil forever if this tree declares none.
				if let liveDebugValues = nodeRenderer.liveDebugValues {
					VStack(alignment: .leading, spacing: 8) {
						ForEach(Array(liveDebugValues.slots.enumerated()), id: \.offset) { index, slot in
							switch slot.kind {
								case .toggle:
									Toggle(debugControlLabel(for: slot), isOn: liveRerendering(liveDebugValues.toggleBinding(at: index)))
								case .slider(let minBound, let maxBound):
									HStack {
										Text(debugControlLabel(for: slot))
											.font(.caption.bold())
											.frame(width: 110, alignment: .leading)
										Slider(value: liveRerendering(liveDebugValues.floatBinding(at: index)),
											   in: Float(minBound)...Float(maxBound))
										Text(String(format: "%.3f", liveDebugValues.values[index]))
											.font(.caption.monospaced())
											.frame(width: 54)
									}
							}
						}
					}
					.padding()
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
				}

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

	// Reads the already-rendered buffer at the nearest pixel instead of
	// live-evaluating the tree at the exact hovered coordinate: there's no
	// more per-coordinate Swift evaluate to call now that rendering is
	// Metal-only (see the Metal codegen migration plan's Phase C). This
	// shows the final composited value at that point rather than the old
	// per-node intermediate breakdown (e.g. Log's numerator/denominator) --
	// a deliberate simplification, not an oversight.
	private func updateDebugInfo(for location: CGPoint, in size: CGSize) {
		self.hoverLocation = location

		let width = Int(nodeRenderer.evaluator.size.width)
		let height = Int(nodeRenderer.evaluator.size.height)
		guard width > 0, height > 0, size.width > 0, size.height > 0 else {
			self.debugInfo = [:]
			return
		}

		let pixelX = min(max(Int((location.x / size.width) * CGFloat(width)), 0), width - 1)
		let pixelY = min(max(Int((location.y / size.height) * CGFloat(height)), 0), height - 1)
		let index = pixelY * width + pixelX

		guard nodeRenderer.data.indices.contains(index) else {
			self.debugInfo = [:]
			return
		}

		self.debugInfo = [
			"pixel": "(\(pixelX), \(pixelY))",
			"value": nodeRenderer.data[index].toDebugString()
		]
	}

	private func updateImage() {
		image = nodeRenderer.cgImage()
	}

	/// Wraps a `LiveDebugValues` binding so setting it also kicks a real
	/// GPU re-render -- `LiveDebugValues.setValue` only writes the new value
	/// into its buffer; nothing else about a control's storage knows this
	/// view exists. Fires on every drag frame, not debounced: the whole
	/// point of the live-uniform buffer is that this is cheap (same
	/// compiled pipeline, just a new dispatch), never a recompile.
	private func liveRerendering<V>(_ binding: Binding<V>) -> Binding<V> {
		Binding(
			get: { binding.wrappedValue },
			set: { newValue in
				binding.wrappedValue = newValue
				Task {
					await nodeRenderer.render()
					updateImage()
				}
			}
		)
	}

	private func debugControlLabel(for slot: DebugControlSlot) -> String {
		"\(slot.templateName).\(slot.paramName)"
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

struct DebugPopoverView: View {
	let debugInfo: [String: String]
	let hoverLocation: CGPoint
	let containerSize: CGSize

	@State private var popoverSize: CGSize = .zero

	var body: some View {
		let isPlacedBelow = hoverLocation.y < (containerSize.height * 0.66)

		ZStack(alignment: isPlacedBelow ? .top : .bottom) {
			VStack(alignment: .leading) {
				ForEach(debugInfo.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
					Text("\(key): \(value)")
						.font(.caption.monospacedDigit())
				}
			}
			.padding(8)
			.background(
				GeometryReader { geo in
					Color.clear
						.onAppear {
							popoverSize = geo.size
						}
				}
			)
			.background(Color(.systemGray))
			.clipShape(RoundedRectangle(cornerRadius: 8))
			.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2)))
			.shadow(radius: 5)

			ArrowShape()
				.fill(Color(.systemGray))
				.frame(width: 20, height: 10)
				.rotationEffect(.degrees(isPlacedBelow ? 0 : 180))
				.offset(y: isPlacedBelow ? -5 : 5)
		}
		.fixedSize()
		.position(
			x: hoverLocation.x,
			y: isPlacedBelow
			? hoverLocation.y + (popoverSize.height / 2 + 10)
			: hoverLocation.y - (popoverSize.height / 2 + 10)
		)
		.transition(.opacity.animation(.easeInOut(duration: 0.1)))
	}
}

struct ArrowShape: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.midX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}

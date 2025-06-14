//
//  RangeSliderView.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/13/25.
//

import SwiftUI
import ExpressionTree

// A small helper to make clamping values more readable.
fileprivate extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

struct RangeSliderView: View {
	let label: String
	@Binding var value: ClosedRange<ComponentType>
	let inBounds: ClosedRange<ComponentType>

	init(label: String,
		 value: Binding<ClosedRange<ComponentType>>,
		 in inBounds: ClosedRange<ComponentType> ) {
		self.label = label
		self._value = value
		self.inBounds = inBounds
	}

	var body: some View {
		// We wrap everything in a VStack to accommodate the new buttons.
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(label)
					.font(.caption.bold())
					.frame(width: 50)

				GeometryReader { geometry in
					let trackWidth = geometry.size.width
					let totalRange = inBounds.upperBound - inBounds.lowerBound

					// This math remains the same
					let lowerThumbPosition = (value.lowerBound - inBounds.lowerBound) / totalRange * ComponentType(trackWidth)
					let upperThumbPosition = (value.upperBound - inBounds.lowerBound) / totalRange * ComponentType(trackWidth)

					let lowerGesture = DragGesture()
						.onChanged { gestureValue in
							let newPosition = gestureValue.location.x
							let rawValue = ComponentType(newPosition / trackWidth) * totalRange + inBounds.lowerBound

							// --- FIX #1: Clamp the new value ---
							let clampedValue = rawValue.clamped(to: inBounds)

							// Prevent thumbs from crossing
							self.value = min(clampedValue, value.upperBound)...value.upperBound
						}

					let upperGesture = DragGesture()
						.onChanged { gestureValue in
							let newPosition = gestureValue.location.x
							let rawValue = ComponentType(newPosition / trackWidth) * totalRange + inBounds.lowerBound

							// --- FIX #1: Clamp the new value ---
							let clampedValue = rawValue.clamped(to: inBounds)

							// Prevent thumbs from crossing
							self.value = value.lowerBound...max(clampedValue, value.lowerBound)
						}

					ZStack(alignment: .leading) {
						// ... The ZStack with the track and thumbs remains the same ...
						Capsule().fill(Color.secondary.opacity(0.2))
						Capsule().fill(Color.accentColor)
							.frame(width: CGFloat(upperThumbPosition - lowerThumbPosition))
							.offset(x: CGFloat(lowerThumbPosition))
						Circle().fill(Color.white).shadow(radius: 2)
							.frame(width: 20, height: 20)
							.offset(x: CGFloat(lowerThumbPosition - 10))
							.gesture(lowerGesture)
						Circle().fill(Color.white).shadow(radius: 2)
							.frame(width: 20, height: 20)
							.offset(x: CGFloat(upperThumbPosition - 10))
							.gesture(upperGesture)
					}
				}
				.frame(height: 20)

				VStack {
					Text(String(format: "%.2f", value.lowerBound))
					Text(String(format: "%.2f", value.upperBound))
				}
				.font(.caption.monospaced())
				.frame(width: 50)
			}

			// --- FIX #2: Add the reset buttons ---
			HStack {
				Spacer() // Pushes the buttons to the right

				Button("Reset (0-1)") {
					// Clamp the default 0-1 range just in case `inBounds` is smaller.
					let lower = ComponentType(0.0).clamped(to: inBounds)
					let upper = ComponentType(1.0).clamped(to: inBounds)
					value = lower...upper
				}

				Button("Full Range") {
					value = inBounds
				}
			}
			.font(.caption)
			.buttonStyle(.bordered)
		}
	}
}


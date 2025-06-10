//
//  GradientDirection.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//  Rewritten with Emboss/Lighting Model on 6/10/25.
//

import Foundation
import simd

public final class GradientDirection: SimpleNode {
	public typealias Coordinate = PixelBuffer.Coordinate
	public typealias Value = PixelBuffer.Value

	private let _children: [Node]

	public init(children: [Node]) {
		assert(children.count == 3)
		self._children = children
	}

	public override var name: String { "gradient-dir" }

	public override var children: [Node] { _children }

	private let delta: Double = 0.005
	private let heightFactor: Double = 200.0
	private let lightZ: Double = 0.5

	public override func evaluatePixel(at coord: Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> Value {
		let source = parameters[0]
		let lightDirXSource = parameters[1]
		let lightDirYSource = parameters[2]

		// MARK: - Step 1: Calculate the Surface Gradient (Gx, Gy)

		// Sample the source "height map" at four neighboring points.
		// We use the luminance of the color as the "height".
		let height_x1 = source.sampleBilinear(at: coord + Coordinate(delta, 0)).averageLuminance()
		let height_x2 = source.sampleBilinear(at: coord - Coordinate(delta, 0)).averageLuminance()
		let Gx = height_x1 - height_x2

		let height_y1 = source.sampleBilinear(at: coord + Coordinate(0, delta)).averageLuminance()
		let height_y2 = source.sampleBilinear(at: coord - Coordinate(0, delta)).averageLuminance()
		let Gy = height_y1 - height_y2

		// --- DEBUGGING HOTSPOT #1 ---
		// If your source noise image is flat, or if delta is too small, Gx and Gy
		// might always be zero. A zero gradient leads to a white image.
		// You could print(Gx) here for a sample coordinate to check.

		// MARK: - Step 2: Form 3D Vectors

		// The surface normal is derived from the gradient. The Z component controls exaggeration.
		// We do NOT normalize it yet.
		let surfaceNormal = SIMD3<Double>(-Gx, -Gy, 1.0 / heightFactor)

		// The light direction comes from the function arguments.
		var lightDx = lightDirXSource.sampleBilinear(at: coord).averageLuminance()
		var lightDy = lightDirYSource.sampleBilinear(at: coord).averageLuminance()

		if lightDx < 0.0006 && lightDy < 0.0006 {
			lightDx = -0.5
			lightDy = 0.5
		}

		let lightDirection = SIMD3<Double>(lightDx, lightDy, lightZ)

		// MARK: - Step 3: Normalize Vectors (Safely!)

		// --- DEBUGGING HOTSPOT #2 ---
		// If the length of a vector is 0, simd_normalize will produce NaN.
		// We must check for this to prevent a white image.

		guard let normal_normalized = simd_normalize(safe: surfaceNormal),
			  let light_normalized = simd_normalize(safe: lightDirection) else {
			// If either vector couldn't be normalized (was zero length),
			// return a neutral gray to indicate an issue, not pure white.
			return Value(repeating: 0.5)
		}

		// MARK: - Step 4: Calculate Shading via Dot Product

		let dotProduct = dot(normal_normalized, light_normalized)

		// --- DEBUGGING HOTSPOT #3 ---
		// If dotProduct is always 1.0, the light and normal vectors are always
		// aligned. Check your gradient and vector math.

		// MARK: - Step 5: Map to Final Color

		// The dot product is in the range [-1, 1]. We map it to [0, 1] for a grayscale color.
		// This is the correct mapping.
		let finalValue = (dotProduct + 1.0) * 0.5

		// Return a gray pixel with the calculated shading value.
		return Value(repeating: finalValue)
	}
}


// MARK: - Safe SIMD Normalize Helper

// Add this helper function to your project. It's invaluable for preventing
// crashes or NaNs from trying to normalize a zero-length vector.
public func simd_normalize(safe vector: SIMD3<Double>) -> SIMD3<Double>? {
	let length = simd_length(vector)
	if length < 1e-9 { // Use a small epsilon for floating point comparison
		return nil
	}
	return vector / length
}

// Add this helper to your PixelBuffer Value extension
fileprivate extension PixelBuffer.Value {
	func averageLuminance() -> Double {
		return (self.x + self.y + self.z) / 3.0
	}
}

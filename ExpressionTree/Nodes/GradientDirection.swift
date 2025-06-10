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
	public typealias CT = PixelBuffer.ComponentType

	private let _children: [Node]

	public init(children: [Node]) {
		assert(children.count == 3)
		self._children = children
	}

	public override var name: String { "gradient-dir" }

	public override var children: [Node] { _children }

	private let delta: CT = 0.005
	private let heightFactor: CT = 200.0
	private let lightZ: CT = 0.5

	public override func evaluatePixel(at coord: Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> Value {
		let source = parameters[0]
		let lightDirXSource = parameters[1]
		let lightDirYSource = parameters[2]

		let height_x1 = source.sampleBilinear(at: coord + Coordinate(delta, 0)).averageLuminance()
		let height_x2 = source.sampleBilinear(at: coord - Coordinate(delta, 0)).averageLuminance()
		let Gx = height_x1 - height_x2

		let height_y1 = source.sampleBilinear(at: coord + Coordinate(0, delta)).averageLuminance()
		let height_y2 = source.sampleBilinear(at: coord - Coordinate(0, delta)).averageLuminance()
		let Gy = height_y1 - height_y2

		let surfaceNormal = Value(-Gx, -Gy, 1.0 / heightFactor)

		var lightDx = lightDirXSource.sampleBilinear(at: coord).averageLuminance()
		var lightDy = lightDirYSource.sampleBilinear(at: coord).averageLuminance()

		if lightDx < 0.0006 && lightDy < 0.0006 {
			lightDx = -0.5
			lightDy = 0.5
		}

		let lightDirection = Value(lightDx, lightDy, lightZ)

		guard let normal_normalized = simd_normalize(safe: surfaceNormal),
			  let light_normalized = simd_normalize(safe: lightDirection) else {
			return Value(repeating: 0.5)
		}

		let dotProduct = dot(normal_normalized, light_normalized)
		let finalValue = (dotProduct + 1.0) * 0.5

		return Value(repeating: finalValue)
	}
}

public func simd_normalize(safe vector: PixelBuffer.Value) -> PixelBuffer.Value? {
	let length = simd_length(vector)
	if length < 1e-9 { // Use a small epsilon for floating point comparison
		return nil
	}
	return vector / length
}

fileprivate extension PixelBuffer.Value {
	func averageLuminance() -> PixelBuffer.ComponentType {
		return (self.x + self.y + self.z) / 3.0
	}
}

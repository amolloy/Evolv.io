//
//  GradientDirection.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//  Rewritten with Emboss/Lighting Model on 6/10/25.
//

import simd

public class GradientDirection: Node {
	public static var name: String {
		return "grad-direction"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 3)
		let result = GradientDirectionResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class GradientDirectionResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult
	let e2: ExpressionResult

	private let delta = ComponentType(0.005)
	private let heightFactor = ComponentType(200.0)
	private let lightZ = ComponentType(0.5)

	init(_ es: [ExpressionResult]) {
		assert(es.count == 3)
		self.e0 = es[0]
		self.e1 = es[1]
		self.e2 = es[2]
	}

	func sampleBilinear(at coord: Coordinate) -> Value {
		let source = e0
		let lightDirXSource = e1.sampleBilinear(at: coord)
		let lightDirYSource = e2.sampleBilinear(at: coord)

		let height_x1 = source.sampleBilinear(at: coord + Coordinate(delta, 0)).averageLuminance()
		let height_x2 = source.sampleBilinear(at: coord - Coordinate(delta, 0)).averageLuminance()
		let Gx = height_x1 - height_x2

		let height_y1 = source.sampleBilinear(at: coord + Coordinate(0, delta)).averageLuminance()
		let height_y2 = source.sampleBilinear(at: coord - Coordinate(0, delta)).averageLuminance()
		let Gy = height_y1 - height_y2

		let surfaceNormal = Value(-Gx, -Gy, 1.0 / heightFactor)

		var lightDx = lightDirXSource.averageLuminance()
		var lightDy = lightDirYSource.averageLuminance()

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

		return Value(repeating: finalValue)	}
}

public func simd_normalize(safe vector: Value) -> Value? {
	let length = simd_length(vector)
	if length < 1e-9 { // Use a small epsilon for floating point comparison
		return nil
	}
	return vector / length
}

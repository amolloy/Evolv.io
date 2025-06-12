//
//  WarpedColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class WarpedColorNoise: Node {
	public static var name: String {
		return "warped-color-noise"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 4)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 4)
		let result = WarperColorNoiseResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class WarperColorNoiseResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult
	let e2: ExpressionResult
	let e3: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 4)
		self.e0 = es[0]
		self.e1 = es[1]
		self.e2 = es[2]
		self.e3 = es[3]
	}

	func sampleBilinear(at coord: Coordinate) -> Value {
		let u = e0.sampleBilinear(at: coord)
		let v = e1.sampleBilinear(at: coord)

		let v0 = e2.sampleBilinear(at: coord) * 50
		let v1 = e3.sampleBilinear(at: coord)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			let sampleCoord = PixelBuffer.Coordinate(u[i], v[i])
			let scaled = sampleCoord * PixelBuffer.Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]) + i)
		}

		return result
	}
}

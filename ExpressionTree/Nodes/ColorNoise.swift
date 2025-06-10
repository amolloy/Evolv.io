//
//  ColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class ColorNoise: Node {
	public var name: String {
		return "color-noise"
	}

	public var children: [any Node]

	public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 2)
		let result = ColorNoiseResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class ColorNoiseResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 2)
		self.e0 = es[0]
		self.e1 = es[1]
	}

	func sampleBilinear(at coord: Coordinate) -> Value {
		let v0 = e0.sampleBilinear(at: coord) * 50
		let v1 = e1.sampleBilinear(at: coord)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			let scaled = coord * PixelBuffer.Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]) + i)
		}

		return result
	}
}

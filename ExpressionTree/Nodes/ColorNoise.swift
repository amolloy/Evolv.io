//
//  ColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class ColorNoise: CachedNode {
	public static var name: String {
		return "color-noise"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 2)
		return ColorNoiseResult(children.map { $0.evaluate(using: evaluator) })
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

	func value(at coord: Coordinate) -> Value {
		let v0 = e0.value(at: coord) * 50
		let v1 = e1.value(at: coord)

		var result = Value(repeating: 0)
		for i in 0..<3 {
			let scaled = coord * Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]) + i)
		}

		return result
	}
}

//
//  WarpedBWNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 8/27/26.
//

import simd

public class WarpedBWNoise: CachedNode {
	public static var name: String {
		return "warped-bw-noise"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 4)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 4)
		return WarperBWNoiseResult(children.map { $0.evaluate(using: evaluator) })
	}
}

class WarperBWNoiseResult: ExpressionResult {
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

	func value(at coord: Coordinate) -> Value {
		let u = e0.value(at: coord)
		let v = e1.value(at: coord)

		let v0 = e2.value(at: coord) * 50
		let v1 = e3.value(at: coord)

		var result = Value(repeating: 0)
		for i in 0..<3 {
			let sampleCoord = Coordinate(u[i], v[i])
			let scaled = sampleCoord * Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]))
		}

		return result
	}
}

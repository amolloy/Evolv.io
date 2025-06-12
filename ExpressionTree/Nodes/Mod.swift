//
//  Mod.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Mod: Node {
	public static var name: String {
		return "mod"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 2)
		let result = ModResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class ModResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 2)
		self.e0 = es[0]
		self.e1 = es[1]
	}

	func value(at coord: Coordinate) -> Value {
		let v0 = e0.value(at: coord)
		let v1 = e1.value(at: coord)

		let isZeroMask = (v1 .== .zero)
		let safeDivisor = v1.replacing(with: 1.0, where: isZeroMask)

		let remainder = fmod(v0, safeDivisor)
		let isNegativeRemainder = remainder .< 0.0
		let positiveRemainder = remainder.replacing(with: remainder + v1, where: isNegativeRemainder)

		return positiveRemainder
	}
}

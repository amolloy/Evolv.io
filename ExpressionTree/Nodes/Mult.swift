//
//  Mult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import simd

public class Mult: Node {
	public var name: String {
		return "*"
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
		let result = MultResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class MultResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 2)
		self.e0 = es[0]
		self.e1 = es[1]
	}

	func sampleBilinear(at coord: Coordinate) -> Value {
		let v0 = e0.sampleBilinear(at: coord)
		let v1 = e1.sampleBilinear(at: coord)

		return v0 * v1
	}
}


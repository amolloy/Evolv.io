//
//  Abs.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Abs: Node {
	public static var name: String {
		return "abs"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 1)
		let result = AbsResult(children[0].evaluate(using: evaluator))

		evaluator.setResult(result, for: self)

		return result
	}
}

class AbsResult: ExpressionResult {
	let e: ExpressionResult

	init(_ e: ExpressionResult) {
		self.e = e
	}

	func value(at coord: Coordinate) -> Value {
		return abs(e.value(at: coord))
	}
}

//
//  Invert.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

public class Invert: CachedNode {
	public static var name: String {
		return "invert"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 1)
		return InvertResult(children[0].evaluate(using: evaluator))
	}
}

class InvertResult: ExpressionResult {
	let e: ExpressionResult

	init(_ e: ExpressionResult) {
		self.e = e
	}

	func value(at coord: Coordinate) -> Value {
		return Value.one / (0.0001 + abs(e.value(at: coord)))
	}
}

//
//  Dissolve.swift
//  Evolv.io
//
//  Created by Andy Molloy on 8/27/26.
//

public class Dissolve: CachedNode {
	public static var name: String {
		return "dissolve"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 3)
		return AddResult(children.map { $0.evaluate(using: evaluator) })
	}
}

class DissolveResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult
	let e2: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 3)
		self.e0 = es[0]
		self.e1 = es[1]
		self.e2 = es[2]
	}

	func value(at coord: Coordinate) -> Value {
		let v0 = e0.value(at: coord)
		let v1 = e2.value(at: coord)
		let w = e1.value(at: coord)

		return (Value.one - w) * v0 + w * v1
	}
}


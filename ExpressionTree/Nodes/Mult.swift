//
//  Mult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public class Mult: CachedNode {
	public static var name: String {
		return "*"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 2)
		return MultResult(children.map { $0.evaluate(using: evaluator) })
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

	func value(at coord: Coordinate) -> Value {
		let v0 = e0.value(at: coord)
		let v1 = e1.value(at: coord)

		return v0 * v1
	}
}

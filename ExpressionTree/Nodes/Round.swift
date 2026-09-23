//
//  Round.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

public class Round: CachedNode {
	public static var name: String {
		return "round"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 2)
		return RoundResult(children.map { $0.evaluate(using: evaluator) })
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		let v0 = children[0].codegenMSL(into: context)
		let v1 = children[1].codegenMSL(into: context)
		// rint (round-to-nearest-even) matches Swift's .rounded(.toNearestOrEven),
		// unlike MSL's round() which rounds ties away from zero.
		let q = context.declare("rint(\(v0.variableName) / \(v1.variableName))")
		return "\(q.variableName) * \(v1.variableName)"
	}
}

class RoundResult: ExpressionResult {
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

		let q = (v0 / v1).rounded(.toNearestOrEven)
		return q * v1
	}
}

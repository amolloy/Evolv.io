//
//  And.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class And: CachedNode {
	public static var name: String {
		return "and"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 2)
		return AndResult( children.map { $0.evaluate(using: evaluator) } )
	}
}

class AndResult: ExpressionResult {
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

		var result = Value(repeating: 0)
		for i in 0..<3 {
			let v0b = ComponentType.toBits(v0[i])
			let v1b = ComponentType.toBits(v1[i])

			result[i] = ComponentType.fromBits(v0b & v1b)
		}

		return result
	}
}

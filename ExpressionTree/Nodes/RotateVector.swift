//
//  RotateVector.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

import Foundation
import simd

public final class RotateVector: CachedNode {
	public static var name: String {
		return "rotate-vector"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		let childResults = children.map { $0.evaluate(using: evaluator) }

		return RotateVectorResult(childResults)
	}
}

class RotateVectorResult: ExpressionResult {
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
		let angle = e0.value(at: coord)
		let x = e1.value(at: coord)
		let y = e2.value(at: coord)

		let pi = ComponentType.pi
		let c = cos(angle * pi)
		let s = sin(angle * pi)

		return c * x + s * y
	}
}

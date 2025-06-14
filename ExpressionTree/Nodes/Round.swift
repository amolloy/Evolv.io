//
//  Round.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

public class Round: Node {
	public static var name: String {
		return "round"
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
		let result = RoundResult(children.map { $0.evaluate(using: evaluator) })
		
		evaluator.setResult(result, for: self)
		
		return result
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
		
		let q = (v0 / v1).rounded(.toNearestOrAwayFromZero)
		return q * v1
	}
}

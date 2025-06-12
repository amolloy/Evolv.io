//
//  If.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class If: Node {
	public static var name: String {
		return "if"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 3)
		let result = IfResult( children.map { $0.evaluate(using: evaluator) } )

		evaluator.setResult(result, for: self)

		return result
	}
}

class IfResult: ExpressionResult {
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
		let condition = e0.value(at: coord)
		let thenVector = e1.value(at: coord)
		let elseVector = e2.value(at: coord)

		var result = Value.zero
		for i in 0..<3 {
			result[i] = condition[i] > 0.0 ? thenVector[i] : elseVector[i]
		}

		return result
	}
}

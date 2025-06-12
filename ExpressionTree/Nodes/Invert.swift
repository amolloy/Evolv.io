//
//  Invert.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class Invert: Node {
	public static var name: String {
		return "invert"
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
		let result = InvertResult(children[0].evaluate(using: evaluator))

		evaluator.setResult(result, for: self)

		return result
	}
}

class InvertResult: ExpressionResult {
	let e: ExpressionResult

	init(_ e: ExpressionResult) {
		self.e = e
	}

	func value(at coord: Coordinate) -> Value {
		return -e.value(at: coord)
	}
}

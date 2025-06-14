//
//  CachedNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

public protocol CachedNode: Node {
	func _evaluate(using evaluator: Evaluator) -> any ExpressionResult
}

extension CachedNode {
	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cached = evaluator.result(for: self) {
			return cached
		}
		let result = _evaluate(using: evaluator)
		evaluator.setResult(result, for: self)
		return result
	}
}


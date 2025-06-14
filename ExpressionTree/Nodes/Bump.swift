//
//  Bump.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

// TODO THIS IS NOT DONNNNEEEE

public class Bump: CachedNode {
	public static var name: String {
		return "bump"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 8)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 8)
		let evaluators = children.map { $0.evaluate(using: evaluator) }
		return LightMapResult(source: evaluators[0],
							  dirX: evaluators[1],
							  dirY: evaluators[2],
							  delta: evaluators[3],
							  heightFactor: evaluators[4],
							  lightZ: evaluators[5])
	}
}

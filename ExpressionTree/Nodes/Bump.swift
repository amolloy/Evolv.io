//
//  Bump.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

// TODO THIS IS NOT DONNNNEEEE

public class Bump: Node {
	public static var name: String {
		return "bump"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 8)
		self.children = children
	}

	/*
	private let delta = ComponentType(0.005)
	private let heightFactor = ComponentType(200.0)
	private let lightZ = ComponentType(0.5)
	 */

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 8)
		let evaluators = children.map { $0.evaluate(using: evaluator) }
		let result = LightMapResult(source: evaluators[0],
									dirX: evaluators[1],
									dirY: evaluators[2],
									delta: evaluators[3],
									heightFactor: evaluators[4],
									lightZ: evaluators[5])

		evaluator.setResult(result, for: self)

		return result
	}
}

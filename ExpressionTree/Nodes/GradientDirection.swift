//
//  GradientDirection.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//  Rewritten with Emboss/Lighting Model on 6/10/25.
//

import simd

public class GradientDirection: Node {
	public static var name: String {
		return "grad-direction"
	}

	public var children: [any Node]

	private let delta = ComponentType(0.005)
	private let heightFactor = ComponentType(200.0)
	private let lightZ = ComponentType(0.5)

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 3)
		let evaluators = children.map { $0.evaluate(using: evaluator) }

		let result = LightMapResult(source: evaluators[0],
									dirX: evaluators[1],
									dirY: evaluators[2],
									delta: ConstantResult(delta),
									heightFactor: ConstantResult(heightFactor),
									lightZ: ConstantResult(lightZ))

		evaluator.setResult(result, for: self)

		return result
	}
}

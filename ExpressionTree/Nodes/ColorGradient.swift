//
//  ColorGradient.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import Foundation
import simd

func mix(_ a: SIMD3<ComponentType>, _ b: SIMD3<ComponentType>, _ t: ComponentType) -> SIMD3<ComponentType> {
	return a + (b - a) * t
}

public final class ColorGradient: CachedNode {
	public static var name: String {
		return "color-grad"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		let arguments = [
			children[0],
			children[1],
			children[2],
			children[3],
			Mult([Constant(100), children[4]]),
		]
		let evaluators = arguments.map { $0.evaluate(using: evaluator) }

		return LightMapResult(source: evaluators[0],
							  dirX: evaluators[1],
							  dirY: evaluators[2],
							  delta: ConstantResult(evaluator.pixelToDotSize(1)),
							  heightFactor: evaluators[4], // ConstantResult(200.0),
							  lightZ: ConstantResult(5),
							  color2: evaluators[3])
	}
}

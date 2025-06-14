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
		let evaluators = children.map { $0.evaluate(using: evaluator) }

		return LightMapResult(source: evaluators[0],
							  dirX: evaluators[1],
							  dirY: evaluators[2],
							  delta: evaluators[3],
							  heightFactor: evaluators[4],
							  lightZ: ConstantResult(0.005))
	}
}

//
//  GradientDirection.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//  Rewritten with Emboss/Lighting Model on 6/10/25.
//

import simd

public class GradientDirection: CachedNode {
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

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 3)

		let evaluators: [ExpressionResult] = [
			children[0].evaluate(using: evaluator),
			PreventZero([children[1], Constant(-0.5)]).evaluate(using: evaluator),
			PreventZero([children[2], Constant(0.5)]).evaluate(using: evaluator)
		]

		return LightMapResult(source: evaluators[0],
							  dirX: evaluators[1],
							  dirY: evaluators[2],
							  delta: ConstantResult(delta),
							  heightFactor: ConstantResult(heightFactor),
							  lightZ: ConstantResult(lightZ),
							  clamp: true)
	}
}

fileprivate class PreventZero: CachedNode {
	public static var name: String {
		return "prevent-zero"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return PreventZeroResult(childExpression: children[0].evaluate(using: evaluator),
								 defaultValue: children[1].evaluate(using: evaluator))
	}
}

fileprivate class PreventZeroResult: ExpressionResult {
	let childExpression: ExpressionResult
	let defaultValue: ExpressionResult

	init(childExpression: ExpressionResult, defaultValue: ExpressionResult) {
		self.childExpression = childExpression
		self.defaultValue = defaultValue
	}

	func value(at coord: Coordinate) -> Value {
		let v = childExpression.value(at: coord)
		let mask = v .== 0.0
		return v.replacing(with: defaultValue.value(at: coord), where: mask)
	}

}


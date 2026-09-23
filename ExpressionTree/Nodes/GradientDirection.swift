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

	private let delta = ComponentType(0.02)
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

	// LightMapResult's `clamp: true` case, specialized: light1/light2 default
	// to ConstantResult(0.0)/(1.0), so `mix(0, 1, t) == t` broadcast across
	// all 3 channels -- the guard-degenerate fallback stays Value(repeating: 0.5)
	// either way, so no separate color mixing step is needed here.
	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 3)
		context.require(.lightingHelpers)

		let sourceFn = context.emitFunction(for: children[0])
		let dirX = PreventZero([children[1], Constant(-0.5)]).codegenMSL(into: context)
		let dirY = PreventZero([children[2], Constant(0.5)]).codegenMSL(into: context)

		let deltaLit = mslFloatLiteral(delta)
		let heightFactorLit = mslFloatLiteral(heightFactor)
		let lightZLit = mslFloatLiteral(lightZ)

		let gx = context.declare("avgLum(\(sourceFn)(coord - float2(\(deltaLit), 0.0))) - avgLum(\(sourceFn)(coord + float2(\(deltaLit), 0.0)))", type: "float")
		let gy = context.declare("avgLum(\(sourceFn)(coord - float2(0.0, \(deltaLit)))) - avgLum(\(sourceFn)(coord + float2(0.0, \(deltaLit))))", type: "float")
		let surfaceNormal = context.declare("float3(-\(gx.variableName), -\(gy.variableName), 1.0 / \(heightFactorLit))")

		let lightDx = context.declare("avgLum(\(dirX.variableName))", type: "float")
		let lightDy = context.declare("avgLum(\(dirY.variableName))", type: "float")
		let lightDirection = context.declare("float3(\(lightDx.variableName), \(lightDy.variableName), \(lightZLit))")

		let normalLen = context.declare("length(\(surfaceNormal.variableName))", type: "float")
		let lightLen = context.declare("length(\(lightDirection.variableName))", type: "float")

		let clampedT = context.declare(
			"clamp((dot(\(surfaceNormal.variableName) / \(normalLen.variableName), \(lightDirection.variableName) / \(lightLen.variableName)) + 1.0) * 0.5, 0.0, 1.0)",
			type: "float")

		return "(\(normalLen.variableName) < 1e-9 || \(lightLen.variableName) < 1e-9) ? float3(0.5) : float3(\(clampedT.variableName))"
	}
}

fileprivate class PreventZero: CachedNode {
	public static var name: String {
		return "prevent-zero"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		// Was asserting count == 1 despite _evaluate always accessing
		// children[1] too -- harmless in Release (assertions stripped, and
		// the array already holds however many elements its caller passed),
		// but would trip in Debug the moment PreventZero's actual 2-element
		// construction below ran. Fixed while touching this node for the
		// Metal codegen migration.
		assert(children.count == 2)
		self.children = children
	}

	func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return PreventZeroResult(childExpression: children[0].evaluate(using: evaluator),
								 defaultValue: children[1].evaluate(using: evaluator))
	}

	func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		let child = children[0].codegenMSL(into: context)
		let defaultVal = children[1].codegenMSL(into: context)
		return "select(\(child.variableName), \(defaultVal.variableName), \(child.variableName) == float3(0.0))"
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


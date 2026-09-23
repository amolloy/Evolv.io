//
//  GradientDirection.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//  Rewritten with Emboss/Lighting Model on 6/10/25.
//

public class GradientDirection: Node {
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

	// This is LightMapResult's `clamp: true` case, specialized: light1/light2
	// default to a black->white mix, so `mix(0, 1, t) == t` broadcast across
	// all 3 channels -- the guard-degenerate fallback stays float3(0.5)
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

/// Replaces a child's value with a default wherever it's exactly zero.
/// Synthesized fresh (not part of the parsed tree) each time
/// `GradientDirection._emitMSL` runs -- see `MSLCodegenContext`'s
/// identity-retention note for why that's safe.
fileprivate class PreventZero: Node {
	public static var name: String {
		return "prevent-zero"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		let child = children[0].codegenMSL(into: context)
		let defaultVal = children[1].codegenMSL(into: context)
		return "select(\(child.variableName), \(defaultVal.variableName), \(child.variableName) == float3(0.0))"
	}
}

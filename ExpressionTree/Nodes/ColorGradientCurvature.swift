//
//  ColorGradientCurvature.swift
//  Evolv.io
//
//  Created by Andy Molloy on 9/23/26.
//
//  Forked out of `color-grad`'s #18 curvature-lighting experiment (see
//  ColorGradient.md #18) into its own node/name so it doesn't clash with
//  `color-grad`'s existing sample-expression test coverage (Figure 9/10/12
//  and 1993 Fig 6 all parse literal "color-grad" calls, and are believed to
//  be the correct shape of the real algorithm). This is *not* a Sims
//  primitive -- it's our own invented variant, kept as its own node because
//  the user found the result interesting even while doubting it's what Sims
//  actually did.
//

public final class ColorGradientCurvature: Node {
	public static var name: String {
		return "color-grad-curvature"
	}

	public static var debugDelta: ComponentType = 0.01
	public static var debugHeightFactor: ComponentType = 20.0
	public static var debugLightZ: ComponentType = 0.0
	public static var debugTapCount: Int = 4

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	// Lights `source` from its *curvature* (2nd finite difference) rather
	// than its *slope* dotted with a light direction -- see ColorGradient.md
	// #18 for the full rationale: a flat/monotonic region's curvature is
	// exactly zero (no hand-tuned baseline needed to get flat regions
	// near-black), and a rounded step edge's two shoulders produce
	// opposite-signed curvature spikes, which `signedPow` below (and,
	// further up an enclosing tree, a `log` change-of-base at a base < 1 --
	// see #12/Experiment C) can turn into two complementary fringe colors
	// on a stroke's two edges.
	//
	// `p1`/`p3` keep `color-grad`'s roles (delta/filter-radius scale,
	// trailing contrast exponent). `p2` is reinterpreted as a curvature
	// *anisotropy* angle -- cos²/sin² of it weight how much the x- vs
	// y-axis curvature contributes -- rather than a light direction, since
	// there's no light vector to aim under this theory. `debugLightZ` is a
	// flat additive baseline (not a light-vector Z component), and
	// `debugHeightFactor` is a direct curvature gain (not a normal-vector
	// Z-scale).
	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 5)
		context.require(.lightingHelpers)

		let sourceFn = context.emitFunction(for: children[0])
		let p1 = children[1].codegenMSL(into: context)
		let p2 = children[2].codegenMSL(into: context)
		let colorTint = children[3].codegenMSL(into: context)
		let p3 = children[4].codegenMSL(into: context)

		let debugDeltaLit = mslFloatLiteral(ColorGradientCurvature.debugDelta)
		let debugHeightFactorLit = mslFloatLiteral(ColorGradientCurvature.debugHeightFactor)
		let debugLightZLit = mslFloatLiteral(ColorGradientCurvature.debugLightZ)

		let p1Val = context.declare("avgLum(\(p1.variableName))", type: "float")
		let deltaLocal = context.declare("(abs(\(p1Val.variableName)) / 3.1) * \(debugDeltaLit)", type: "float")

		let p3Val = context.declare("avgLum(\(p3.variableName))", type: "float")
		let heightFactor = context.declare("\(p3Val.variableName) * \(debugHeightFactorLit)", type: "float")
		let lightZ = context.declare("\(p3Val.variableName) * \(debugLightZLit)", type: "float")

		let angle = context.declare("avgLum(\(p2.variableName))", type: "float")

		let tapCount = max(1, ColorGradientCurvature.debugTapCount)
		let tapCountLit = mslFloatLiteral(ComponentType(tapCount))

		let center = context.declare("\(sourceFn)(coord)")

		var xCurvTerms: [String] = []
		var yCurvTerms: [String] = []
		for i in 1...tapCount {
			let fracLit = mslFloatLiteral(ComponentType(i) / ComponentType(tapCount))
			let radius = context.declare("\(deltaLocal.variableName) * \(fracLit)", type: "float")

			let hXNeg = context.declare("\(sourceFn)(coord - float2(\(radius.variableName), 0.0))")
			let hXPos = context.declare("\(sourceFn)(coord + float2(\(radius.variableName), 0.0))")
			xCurvTerms.append("(\(hXNeg.variableName) + \(hXPos.variableName) - 2.0 * \(center.variableName))")

			let hYNeg = context.declare("\(sourceFn)(coord - float2(0.0, \(radius.variableName)))")
			let hYPos = context.declare("\(sourceFn)(coord + float2(0.0, \(radius.variableName)))")
			yCurvTerms.append("(\(hYNeg.variableName) + \(hYPos.variableName) - 2.0 * \(center.variableName))")
		}
		let curvX = context.declare("(\(xCurvTerms.joined(separator: " + "))) / \(tapCountLit)")
		let curvY = context.declare("(\(yCurvTerms.joined(separator: " + "))) / \(tapCountLit)")

		let weightX = context.declare("cos(\(angle.variableName)) * cos(\(angle.variableName))", type: "float")
		let weightY = context.declare("sin(\(angle.variableName)) * sin(\(angle.variableName))", type: "float")
		let curvature = context.declare("\(weightX.variableName) * \(curvX.variableName) + \(weightY.variableName) * \(curvY.variableName)")

		let lightMap = context.declare("\(colorTint.variableName) * (\(heightFactor.variableName) * \(curvature.variableName) + \(lightZ.variableName))")

		return "signedPow(\(lightMap.variableName), \(p3Val.variableName))"
	}
}

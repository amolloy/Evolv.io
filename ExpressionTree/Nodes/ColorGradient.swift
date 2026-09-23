//
//  ColorGradient.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public final class ColorGradient: Node {
	public static var name: String {
		return "color-grad"
	}

	// Temporary debug knobs so ColorGradientDebugView can tune these live;
	// revert to the plain literals below (0.01 / 3 / 0.04) once done experimenting.
	public static var debugDelta: ComponentType = 0.01
	// heightFactor/lightZ are p3 * these multipliers (see #14 in
	// ColorGradient.md), not absolute values. First shared setting found
	// to give decent results on both Figure 9 and Figure 10 at once (see
	// #14's checkpoint note) -- heightFactor=20 means an actual heightFactor
	// of 27 for Figure 9's calls (p3=1.35) vs. 60.6 for Figure 10's (p3=3.03).
	public static var debugHeightFactor: ComponentType = 20.0
	public static var debugLightZ: ComponentType = 0.0
	// Number of finite-difference taps per axis between the center and
	// `deltaLocal` (see ColorGradient.md's "more samples between the delta
	// endpoints" experiment) -- e.g. 4 samples at delta*(1/4, 2/4, 3/4, 1),
	// averaged with equal weight, instead of the previous fixed two-tap
	// 0.6*inner + 0.4*outer blend. `debugTapCount = 1` reproduces a plain
	// single central difference at the full delta radius; `2` is close to
	// (but not identical to, since weights are now equal) the old scheme.
	public static var debugTapCount: Int = 4

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	// source/p1/p2 line up 1:1 with grad-direction's source/dirX/dirY.
	// delta is wider than grad-direction's 0.005 for the reason noted
	// historically: color-grad is always fed round's output, a true step
	// function, and 0.02 better matches the band widths in Sims'
	// reference figures than 0.005 did. `color` fills the colorization
	// grad-direction has no room for.
	//
	// heightFactor/lightZ are p3 * debugHeightFactor/debugLightZ (see #14 in
	// ColorGradient.md) rather than pure global constants -- p3 already
	// varies substantially between calls (1.35 for both of Figure 9's, 3.03
	// for Figure 10) and was otherwise only spent on the trailing contrast
	// exponent below, reused here so one shared debug setting can (in
	// principle) fit multiple figures without per-figure hand-tuning.
	//
	// debugHeightFactor/debugLightZ/debugDelta are baked in as codegen-time
	// literals here, not live uniforms -- MetalRenderContext's pipeline cache
	// key includes their current values specifically so a
	// ColorGradientDebugView slider drag can't silently serve a stale
	// pipeline, but it does mean a slider drag recompiles this tree. Promoting
	// these to a real uniform buffer (so a drag only changes a buffer, never
	// the generated MSL, and the cache key can go back to just the tree
	// shape) is deferred follow-up work, not required for correctness.
	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 5)
		context.require(.lightingHelpers)

		let sourceFn = context.emitFunction(for: children[0])
		let p1 = children[1].codegenMSL(into: context)
		let p2 = children[2].codegenMSL(into: context)
		let colorTint = children[3].codegenMSL(into: context)
		let p3 = children[4].codegenMSL(into: context)

		let debugDeltaLit = mslFloatLiteral(ColorGradient.debugDelta)
		let debugHeightFactorLit = mslFloatLiteral(ColorGradient.debugHeightFactor)
		let debugLightZLit = mslFloatLiteral(ColorGradient.debugLightZ)

		let p1Val = context.declare("avgLum(\(p1.variableName))", type: "float")
		let deltaLocal = context.declare("(abs(\(p1Val.variableName)) / 3.1) * \(debugDeltaLit)", type: "float")

		let p3Val = context.declare("avgLum(\(p3.variableName))", type: "float")
		let heightFactor = context.declare("\(p3Val.variableName) * \(debugHeightFactorLit)", type: "float")
		let lightZ = context.declare("\(p3Val.variableName) * \(debugLightZLit)", type: "float")

		let angle = context.declare("avgLum(\(p2.variableName))", type: "float")

		// Multi-tap gradient estimate: sample `source` at `tapCount` radii
		// evenly spaced between the center and `deltaLocal` (delta * 1/N,
		// 2/N, ..., N/N), average the resulting central differences with
		// equal weight. Generalizes the old fixed two-tap
		// 0.6*inner + 0.4*outer blend to an arbitrary, live-tunable sample
		// count (ColorGradient.debugTapCount) -- see ColorGradient.md.
		let tapCount = max(1, ColorGradient.debugTapCount)
		var xDiffTerms: [String] = []
		var yDiffTerms: [String] = []
		for i in 1...tapCount {
			let fracLit = mslFloatLiteral(ComponentType(i) / ComponentType(tapCount))
			let radius = context.declare("\(deltaLocal.variableName) * \(fracLit)", type: "float")

			let hXNeg = context.declare("\(sourceFn)(coord - float2(\(radius.variableName), 0.0))")
			let hXPos = context.declare("\(sourceFn)(coord + float2(\(radius.variableName), 0.0))")
			xDiffTerms.append("(\(hXNeg.variableName) - \(hXPos.variableName))")

			let hYNeg = context.declare("\(sourceFn)(coord - float2(0.0, \(radius.variableName)))")
			let hYPos = context.declare("\(sourceFn)(coord + float2(0.0, \(radius.variableName)))")
			yDiffTerms.append("(\(hYNeg.variableName) - \(hYPos.variableName))")
		}
		let tapCountLit = mslFloatLiteral(ComponentType(tapCount))
		let gx = context.declare("(\(xDiffTerms.joined(separator: " + "))) / \(tapCountLit)")
		let gy = context.declare("(\(yDiffTerms.joined(separator: " + "))) / \(tapCountLit)")

		let lightDx = context.declare("cos(\(angle.variableName))", type: "float")
		let lightDy = context.declare("sin(\(angle.variableName))", type: "float")
		let lightDir = context.declare("float3(\(lightDx.variableName), \(lightDy.variableName), \(lightZ.variableName))")
		let lightLen = context.declare("length(\(lightDir.variableName))", type: "float")
		let lightNormalized = context.declare("\(lightDir.variableName) / \(lightLen.variableName)")

		let lightMap = context.declare("""
		(\(lightLen.variableName) < 1e-9) ? float3(0.5) : float3(
			colorGradChannel(\(gx.variableName).x, \(gy.variableName).x, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).x),
			colorGradChannel(\(gx.variableName).y, \(gy.variableName).y, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).y),
			colorGradChannel(\(gx.variableName).z, \(gy.variableName).z, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).z))
		""")

		return "signedPow(\(lightMap.variableName), \(p3Val.variableName))"
	}
}

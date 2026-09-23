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

// `heightFactor`/`lightZ` used to be pure global debug constants -- the
// same value for every color-grad call in every figure, which architecturally
// can't express "Figure 9 wants one steepness/light-height, Figure 10 wants
// another." This scales `p3` (otherwise only used downstream as a contrast
// exponent -- see ColorGradResult) by a live debug multiplier instead, so
// each call's own already-varying p3 (1.35 for Figure 9's two calls, 3.03
// for Figure 10) drives a genuinely different value per call.
private struct ScaledResult: ExpressionResult {
	let base: ExpressionResult
	let scale: ComponentType

	func value(at coord: Coordinate) -> Value {
		return base.value(at: coord) * scale
	}
}

// Per-channel treatment: source's R/G/B as three independent heightmaps
// instead of collapsing them to one scalar via averageLuminance() before
// doing the finite-difference/lighting math. Real, meaningful effect
// whenever source's channels actually differ (e.g. the outer color-grad's
// source, which inherits per-channel tint from the inner color-grad) --
// letting each channel see its own local slope instead of forcing all three
// to move in lockstep. A Blinn-Phong specular kicker was tried on top of
// this and removed (see ColorGradient.md); this plain diffuse mix (black ->
// color, contrast exponent p3) is the last version that looked like a
// genuine step forward rather than a wash.
private struct PerChannelLightMapResult: ExpressionResult {
	let source: ExpressionResult
	let theta: ExpressionResult
	let delta: ExpressionResult
	let heightFactor: ExpressionResult
	let lightZ: ExpressionResult
	let color: ExpressionResult

	func value(at coord: Coordinate) -> Value {
		let p1Val = self.delta.value(at: coord).averageLuminance()
		let delta = (abs(p1Val) / 3.1) * ColorGradient.debugDelta
		let heightFactor = self.heightFactor.value(at: coord).averageLuminance()
		let lightZ = self.lightZ.value(at: coord).averageLuminance()
		let angle = theta.value(at: coord).averageLuminance()
		let lightDx = cos(angle)
		let lightDy = sin(angle)

		guard let lightNormalized = simd_normalize(safe: Value(lightDx, lightDy, lightZ)) else {
			return Value(repeating: 0.5)
		}

		// Multi-tap smoothed sampling across delta:
		// Sampling at inner (0.5 * delta) and outer (1.0 * delta) produces
		// continuous slope across step edges, creating smoothly rounded 3D tubes
		// instead of a flat binary chamfer.
		let dInner = delta * 0.5
		let dOuter = delta

		let hXNegOuter = source.value(at: coord - Coordinate(dOuter, 0))
		let hXNegInner = source.value(at: coord - Coordinate(dInner, 0))
		let hXPosInner = source.value(at: coord + Coordinate(dInner, 0))
		let hXPosOuter = source.value(at: coord + Coordinate(dOuter, 0))

		let hYNegOuter = source.value(at: coord - Coordinate(0, dOuter))
		let hYNegInner = source.value(at: coord - Coordinate(0, dInner))
		let hYPosInner = source.value(at: coord + Coordinate(0, dInner))
		let hYPosOuter = source.value(at: coord + Coordinate(0, dOuter))

		let colorVal = color.value(at: coord)

		if ColorGradient.debugSharedNormal {
			// Collapse to one shared scalar height field (grad-direction's
			// approach) before differencing, so every channel sees the same
			// normal/t and only `color` distinguishes them -- tests whether
			// per-channel sign divergence (the else branch below) is what's
			// scrambling hues into ones Sims' figures don't show.
			let gxInner = hXNegInner.averageLuminance() - hXPosInner.averageLuminance()
			let gxOuter = hXNegOuter.averageLuminance() - hXPosOuter.averageLuminance()
			let gx = 0.6 * gxInner + 0.4 * gxOuter

			let gyInner = hYNegInner.averageLuminance() - hYPosInner.averageLuminance()
			let gyOuter = hYNegOuter.averageLuminance() - hYPosOuter.averageLuminance()
			let gy = 0.6 * gyInner + 0.4 * gyOuter

			guard let normal = simd_normalize(safe: Value(-gx, -gy, 1.0 / heightFactor)) else {
				return Value(repeating: 0.5)
			}

			let t = dot(normal, lightNormalized)
			return colorVal * t
		}

		var result = Value.zero
		for i in 0..<3 {
			let gxInner = hXNegInner[i] - hXPosInner[i]
			let gxOuter = hXNegOuter[i] - hXPosOuter[i]
			let gx = 0.6 * gxInner + 0.4 * gxOuter

			let gyInner = hYNegInner[i] - hYPosInner[i]
			let gyOuter = hYNegOuter[i] - hYPosOuter[i]
			let gy = 0.6 * gyInner + 0.4 * gyOuter

			guard let normal = simd_normalize(safe: Value(-gx, -gy, 1.0 / heightFactor)) else {
				result[i] = 0.5
				continue
			}

			let t = dot(normal, lightNormalized)
			result[i] = colorVal[i] * t
		}
		return result
	}
}

class ColorGradResult: ExpressionResult {
	let lightMap: ExpressionResult
	let exponent: ExpressionResult

	init(lightMap: ExpressionResult, exponent: ExpressionResult) {
		self.lightMap = lightMap
		self.exponent = exponent
	}

	func value(at coord: Coordinate) -> Value {
		let base = lightMap.value(at: coord)
		let p3Val = exponent.value(at: coord).averageLuminance()

		var result = Value.zero
		for i in 0..<3 {
			let signVal: ComponentType = base[i] < 0 ? -1.0 : 1.0
			result[i] = signVal * pow(abs(base[i]), p3Val)
		}
		return result
	}
}

public final class ColorGradient: CachedNode {
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
	// Experiment: does letting each channel's normal/t diverge in sign from
	// the others (current per-channel default) scramble hues that should be
	// coherent? true collapses the gradient to one shared scalar height field
	// (like grad-direction) and tints the single resulting t by `color`.
	public static var debugSharedNormal: Bool = false

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		let evaluators = children.map { $0.evaluate(using: evaluator) }

		// source/p1/p2 line up 1:1 with grad-direction's source/dirX/dirY.
		// delta is wider than grad-direction's 0.005 for the reason noted
		// historically: color-grad is always fed round's output, a true step
		// function, and 0.02 better matches the band widths in Sims'
		// reference figures than 0.005 did. `color` fills the colorization
		// grad-direction has no room for.
		//
		// Experiment (#14 in ColorGradient.md): heightFactor/lightZ used to
		// be pure global debug constants, identical for every call in every
		// figure -- architecturally incapable of giving Figure 9 and Figure
		// 10 different steepness/light-height even though tuning them by
		// hand for each figure separately suggested they need to differ.
		// p3 already varies substantially between calls (1.35 for both of
		// Figure 9's, 3.03 for Figure 10's) and was otherwise only spent on
		// ColorGradResult's trailing contrast exponent -- reused here to
		// scale heightFactor/lightZ too, so one consistent formula can (in
		// principle) fit multiple figures without per-figure hand-tuning.
		let p3 = evaluators[4]
		let lightMap = PerChannelLightMapResult(source: evaluators[0],
									  theta: evaluators[2],
									  delta: evaluators[1],
									  heightFactor: ScaledResult(base: p3, scale: ColorGradient.debugHeightFactor),
									  lightZ: ScaledResult(base: p3, scale: ColorGradient.debugLightZ),
									  color: evaluators[3])

		return ColorGradResult(lightMap: lightMap, exponent: p3)
	}

	// debugHeightFactor/debugLightZ/debugDelta are baked in as literals at
	// codegen time here, not read as live uniforms -- correct for proving
	// the math translation (this file's parity tests), but means a
	// ColorGradientDebugView slider drag would need this tree recompiled to
	// take effect, unlike the CPU path. Promoting these to a real uniform
	// buffer bound at dispatch time (so slider drags only change a buffer,
	// never the generated MSL) is production-render-path work for the
	// Phase B cutover, not needed yet while Swift math is still what
	// actually renders.
	//
	// debugSharedNormal's `true` branch (PerChannelLightMapResult.value's
	// collapsed-normal path) isn't ported -- fails loudly rather than
	// silently producing wrong output if it's ever flipped before this gets
	// addressed.
	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 5)
		precondition(!ColorGradient.debugSharedNormal, "color-grad's debugSharedNormal=true path isn't ported to Metal codegen yet")
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
		let dInner = context.declare("\(deltaLocal.variableName) * 0.5", type: "float")

		let p3Val = context.declare("avgLum(\(p3.variableName))", type: "float")
		let heightFactor = context.declare("\(p3Val.variableName) * \(debugHeightFactorLit)", type: "float")
		let lightZ = context.declare("\(p3Val.variableName) * \(debugLightZLit)", type: "float")

		let angle = context.declare("avgLum(\(p2.variableName))", type: "float")

		let hXNegOuter = context.declare("\(sourceFn)(coord - float2(\(deltaLocal.variableName), 0.0))")
		let hXNegInner = context.declare("\(sourceFn)(coord - float2(\(dInner.variableName), 0.0))")
		let hXPosInner = context.declare("\(sourceFn)(coord + float2(\(dInner.variableName), 0.0))")
		let hXPosOuter = context.declare("\(sourceFn)(coord + float2(\(deltaLocal.variableName), 0.0))")
		let hYNegOuter = context.declare("\(sourceFn)(coord - float2(0.0, \(deltaLocal.variableName)))")
		let hYNegInner = context.declare("\(sourceFn)(coord - float2(0.0, \(dInner.variableName)))")
		let hYPosInner = context.declare("\(sourceFn)(coord + float2(0.0, \(dInner.variableName)))")
		let hYPosOuter = context.declare("\(sourceFn)(coord + float2(0.0, \(deltaLocal.variableName)))")

		let lightDx = context.declare("cos(\(angle.variableName))", type: "float")
		let lightDy = context.declare("sin(\(angle.variableName))", type: "float")
		let lightDir = context.declare("float3(\(lightDx.variableName), \(lightDy.variableName), \(lightZ.variableName))")
		let lightLen = context.declare("length(\(lightDir.variableName))", type: "float")
		let lightNormalized = context.declare("\(lightDir.variableName) / \(lightLen.variableName)")

		let lightMap = context.declare("""
		(\(lightLen.variableName) < 1e-9) ? float3(0.5) : float3(
			colorGradChannel(\(hXNegOuter.variableName).x, \(hXNegInner.variableName).x, \(hXPosInner.variableName).x, \(hXPosOuter.variableName).x, \(hYNegOuter.variableName).x, \(hYNegInner.variableName).x, \(hYPosInner.variableName).x, \(hYPosOuter.variableName).x, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).x),
			colorGradChannel(\(hXNegOuter.variableName).y, \(hXNegInner.variableName).y, \(hXPosInner.variableName).y, \(hXPosOuter.variableName).y, \(hYNegOuter.variableName).y, \(hYNegInner.variableName).y, \(hYPosInner.variableName).y, \(hYPosOuter.variableName).y, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).y),
			colorGradChannel(\(hXNegOuter.variableName).z, \(hXNegInner.variableName).z, \(hXPosInner.variableName).z, \(hXPosOuter.variableName).z, \(hYNegOuter.variableName).z, \(hYNegInner.variableName).z, \(hYPosInner.variableName).z, \(hYPosOuter.variableName).z, \(heightFactor.variableName), \(lightNormalized.variableName), \(colorTint.variableName).z))
		""")

		return "signedPow(\(lightMap.variableName), \(p3Val.variableName))"
	}
}

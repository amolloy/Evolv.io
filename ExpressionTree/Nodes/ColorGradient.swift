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

// Per-channel treatment: source's R/G/B as three independent heightmaps
// instead of collapsing them to one scalar via averageLuminance() before
// doing the finite-difference/lighting math. Real, meaningful effect
// whenever source's channels actually differ (e.g. the outer color-grad's
// source, which inherits per-channel tint from the inner color-grad) --
// letting each channel see its own local slope instead of forcing all three
// to move in lockstep. Phong specular was tried on top of this and reverted;
// this plain diffuse mix (black -> color, contrast exponent p3) is the last
// version that looked like a genuine step forward rather than a wash.
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

		let V = Value(0, 0, 1)
		guard let lightNormalized = simd_normalize(safe: Value(lightDx, lightDy, lightZ)),
			  let halfVector = simd_normalize(safe: lightNormalized + V) else {
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

			let tDiffuse = dot(normal, lightNormalized)
			var t = tDiffuse
			if ColorGradient.debugSpecular > 0 {
				let nDotH = max(0.0, dot(normal, halfVector))
				t += pow(nDotH, ColorGradient.debugShininess) * ColorGradient.debugSpecular
			}
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
	public static var debugDelta: ComponentType = 0.02
	public static var debugHeightFactor: ComponentType = 15.0
	public static var debugLightZ: ComponentType = 0.0
	public static var debugSpecular: ComponentType = 0.0
	public static var debugShininess: ComponentType = 8.0

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		let evaluators = children.map { $0.evaluate(using: evaluator) }

		// source/p1/p2 line up 1:1 with grad-direction's source/dirX/dirY, and
		// grad-direction is a verified match for Sims' own algorithm (he
		// publishes its output directly as figure 4h), so its heightFactor
		// and lightZ are reused here as-is rather than guessed at again.
		// delta is wider than grad-direction's 0.005: color-grad is always
		// fed round's output, a true step function, so the width of the
		// resulting dark band is roughly 2*delta in coordinate space --
		// 0.005 produced 1-2px bands, but Sims' reference figures show bands
		// tens of pixels wide with a colored fringe at the edges, matched by
		// 0.02 at our render resolution. `color` fills the colorization
		// grad-direction has no room for. That leaves p3 as the one truly
		// new argument -- applied here as a contrast/gamma exponent on the
		// final lit color, since grad-direction's 3-argument signature has
		// no structural room left for it to mean anything else.
		let lightMap = PerChannelLightMapResult(source: evaluators[0],
									  theta: evaluators[2],
									  delta: evaluators[1],
									  heightFactor: ConstantResult(ColorGradient.debugHeightFactor),
									  lightZ: ConstantResult(ColorGradient.debugLightZ),
									  color: evaluators[3])

		return ColorGradResult(lightMap: lightMap, exponent: evaluators[4])
	}
}

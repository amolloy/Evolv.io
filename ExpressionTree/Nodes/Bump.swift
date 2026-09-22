//
//  Bump.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//  Reordered per Bump.md #5/#6 on 9/22/26.
//

import simd

public class Bump: CachedNode {
	public static var name: String {
		return "bump"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 8)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 8)
		let evaluators = children.map { $0.evaluate(using: evaluator) }
		return NormalBumpResult(source: evaluators[0],
								multiplier: evaluators[1],
								strength: evaluators[2],
								color1: evaluators[3],
								color2: evaluators[4],
								dirX: evaluators[5],
								dirY: evaluators[6],
								lightHeight: evaluators[7])
	}
}

// See Bump.md #5/#6: the argument shapes across all three known `bump`
// calls (one sub-expression, then vector/scalar/vector/vector/scalar/
// scalar/scalar) rule out the original source/dirX/dirY/color1/color2/
// lightZ/heightFactor/delta mapping -- `color1`/`color2` need an adjacent
// vector/vector pair (only positions 4-5 fit) and a `dirX`/`dirY`-style
// adjacent scalar pair can only come from positions 6/7/8. This reads
// `source` directly as a normal (no finite-differencing -- classic
// normal-mapping rather than height-field bump-mapping), scaled by a
// `multiplier` vector and blended against a flat `(0,0,1)` normal by
// `strength` before lighting against `(dirX, dirY, lightHeight)`.
// `multiplier`/`strength` are placeholder guesses (Bump.md #6) -- nothing
// else fit those slots, not confirmed roles. Known flaw, logged in
// Bump.md #6: `source` is a pure scalar-broadcast expression in both
// checkable calls (Figure 10, Figure 12a), so `normalize(source)` is a
// fixed +/- direction, not a real field, regardless of `multiplier`.
class NormalBumpResult: ExpressionResult {
	let source: ExpressionResult
	let multiplier: ExpressionResult
	let strength: ExpressionResult
	let color1: ExpressionResult
	let color2: ExpressionResult
	let dirX: ExpressionResult
	let dirY: ExpressionResult
	let lightHeight: ExpressionResult

	init(source: ExpressionResult,
		 multiplier: ExpressionResult,
		 strength: ExpressionResult,
		 color1: ExpressionResult,
		 color2: ExpressionResult,
		 dirX: ExpressionResult,
		 dirY: ExpressionResult,
		 lightHeight: ExpressionResult) {
		self.source = source
		self.multiplier = multiplier
		self.strength = strength
		self.color1 = color1
		self.color2 = color2
		self.dirX = dirX
		self.dirY = dirY
		self.lightHeight = lightHeight
	}

	func value(at coord: Coordinate) -> Value {
		let multiplierVal = multiplier.value(at: coord)
		let strengthVal = strength.value(at: coord).averageLuminance()
		let dirXVal = dirX.value(at: coord).averageLuminance()
		let dirYVal = dirY.value(at: coord).averageLuminance()
		let lightHeightVal = lightHeight.value(at: coord).averageLuminance()

		let scaledSource = source.value(at: coord) * multiplierVal
		let flatNormal = Value(0, 0, 1)
		let computedNormal = simd_normalize(safe: scaledSource) ?? flatNormal

		guard let normal = simd_normalize(safe: mix(flatNormal, computedNormal, t: strengthVal)),
			  let light = simd_normalize(safe: Value(dirXVal, dirYVal, lightHeightVal)) else {
			return Value(repeating: 0.5)
		}

		let t = simd_clamp((dot(normal, light) + 1.0) * 0.5, 0.0, 1.0)

		return mix(color1.value(at: coord), color2.value(at: coord), t: t)
	}
}

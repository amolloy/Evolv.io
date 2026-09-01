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
		let lightMap = LightMapResult(source: evaluators[0],
									  dirX: evaluators[1],
									  dirY: evaluators[2],
									  delta: ConstantResult(0.02),
									  heightFactor: ConstantResult(200.0),
									  lightZ: ConstantResult(0.5),
									  color2: evaluators[3],
									  clamp: false)

		return ColorGradResult(lightMap: lightMap, exponent: evaluators[4])
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
			result[i] = pow(abs(base[i]), p3Val)
		}
		return result
	}
}

//
//  HSVToRGB.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

import simd

public class HSVToRGB: CachedNode {
	public static var name: String {
		return "hsv-to-rgb"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 1)
		return HSVToRGBResult(children[0].evaluate(using: evaluator))
	}
}

class HSVToRGBResult: ExpressionResult {
	let e: ExpressionResult

	init(_ e: ExpressionResult) {
		self.e = e
	}

	func value(at coord: Coordinate) -> Value {
		let hsv = e.value(at: coord)
		let h = hsv.x.truncatingRemainder(dividingBy: 1.0) * 6.0
		let s = hsv.y
		let v = hsv.z

		let c = v * s
		let x = c * (1.0 - abs((h.truncatingRemainder(dividingBy: 2.0)) - 1.0))
		let m = v - c

		let rgb: SIMD3<Double>
		switch Int(h) {
			case 0: rgb = SIMD3(c, x, 0)
			case 1: rgb = SIMD3(x, c, 0)
			case 2: rgb = SIMD3(0, c, x)
			case 3: rgb = SIMD3(0, x, c)
			case 4: rgb = SIMD3(x, 0, c)
			case 5: rgb = SIMD3(c, 0, x)
			default: rgb = SIMD3(0, 0, 0)
		}

		return rgb + SIMD3(repeating: m)
	}
}

//
//  ColorGradient.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import Foundation
import simd

public final class ColorGradient: Node {
	public static var name: String {
		return "color-grad"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		let childResults = children.map { $0.evaluate(using: evaluator) }

		return ColorGradientResult(childResults)
	}
}

class ColorGradientResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult
	let e2: ExpressionResult
	let e3: ExpressionResult
	let e4: ExpressionResult

	private let delta = ComponentType(0.005)
	private let heightFactor = ComponentType(5.0)
	private let lightZ = ComponentType(0.5)

	init(_ es: [ExpressionResult]) {
		assert(es.count == 3)
		self.e0 = es[0]
		self.e1 = es[1]
		self.e2 = es[2]
		self.e3 = es[3]
		self.e4 = es[4]
	}

	func value(at coord: Coordinate) -> Value {
		let c1 = e3.value(at: coord)
		let c2 = e4.value(at: coord)

		let lightDirXSource = e1.value(at: coord)
		let lightDirYSource = e2.value(at: coord)

		let surfaceNormal = e0.value(at: coord)

		var lightDx = lightDirXSource.averageLuminance()
		var lightDy = lightDirYSource.averageLuminance()

		if lightDx < 0.0006 && lightDy < 0.0006 {
			lightDx = -0.5
			lightDy = 0.5
		}

		let lightDirection = Value(lightDx, lightDy, lightZ)

		guard let normal_normalized = simd_normalize(safe: surfaceNormal),
			  let light_normalized = simd_normalize(safe: lightDirection) else {
			return Value(repeating: 0.5)
		}

		let dotProduct = dot(normal_normalized, light_normalized)
		let finalValue = (dotProduct + 1.0) * 0.5

		return simd_mix(c1, c2, Value(repeating: finalValue))
	}
}

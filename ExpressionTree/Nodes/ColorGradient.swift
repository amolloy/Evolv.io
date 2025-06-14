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
		assert(es.count == 5)
		self.e0 = es[0]
		self.e1 = es[1]
		self.e2 = es[2]
		self.e3 = es[3]
		self.e4 = es[4]
	}
	
	func value(at coord: Coordinate) -> Value {
		let pos = e0.value(at: coord)
		let low = e1.value(at: coord).averageLuminance()
		let high = e2.value(at: coord).averageLuminance()
		let baseColor = e3.value(at: coord)
		let scale = e4.value(at: coord).averageLuminance()
		
		// Extract luminance from pos
		let luminance = pos.averageLuminance()
		
		// Normalize
		let t = min(max((luminance - low) / (high - low), 0.0), 1.0)
		
		// Interpolate between black and baseColor
		let finalColor = mix(SIMD3<ComponentType>(repeating: 0.0), baseColor, t * scale)
		return finalColor
	}
}

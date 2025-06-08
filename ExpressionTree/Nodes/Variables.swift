//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

class VariableX: SimpleNode, Node {
	let name = "x"

	override func evaluatePixel(x: Float, y: Float) -> SIMD3<Float> {
		return SIMD3<Float>(x, x, x)
	}
}

class VariableY: SimpleNode, Node {
	let name = "y"

	override func evaluatePixel(x: Float, y: Float) -> SIMD3<Float> {
		return SIMD3<Float>(y, y, y)
	}
}

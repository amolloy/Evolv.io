//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

class Constant: SimpleNode, Node {
	let name = "constant"
	let value: Float

	init(value: Float) {
		self.value = value
	}

	override func evaluatePixel(x: Float, y: Float) -> SIMD3<Float> {
		return SIMD3<Float>(value, value, value)
	}
}

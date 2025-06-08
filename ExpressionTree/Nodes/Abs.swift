//
//  Abs.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

class Abs: SimpleNode, Node {
	let name = "abs"

	override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		assert(parameters.count == 1)

		let v = parameters[0].sampleBilinear(u: x, v: y)
		return abs(v)
	}
}

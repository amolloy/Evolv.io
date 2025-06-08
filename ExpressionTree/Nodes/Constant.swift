//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

class Constant: SimpleNode, Node {
	let name = "constant"
	let value: PixelBuffer.ComponentType

	init(value: PixelBuffer.ComponentType) {
		self.value = value
	}

	override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(PixelBuffer.ComponentType(value),
								 PixelBuffer.ComponentType(value),
								 PixelBuffer.ComponentType(value))
	}
}

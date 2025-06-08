//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

class VariableX: SimpleNode, Node {
	let name = "x"

	override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(PixelBuffer.ComponentType(x),
								 PixelBuffer.ComponentType(x),
								 PixelBuffer.ComponentType(x))
	}
}

class VariableY: SimpleNode, Node {
	let name = "y"

	override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(PixelBuffer.ComponentType(y),
								 PixelBuffer.ComponentType(y),
								 PixelBuffer.ComponentType(y))
	}
}

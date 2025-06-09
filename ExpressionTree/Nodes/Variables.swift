//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class VariableX: SimpleNode, Node {
	public let name = "x"

	public override init() {
	}

	public override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(PixelBuffer.ComponentType(x),
								 PixelBuffer.ComponentType(x),
								 PixelBuffer.ComponentType(x))
	}
}

public class VariableY: SimpleNode, Node {
	public let name = "y"
	
	public override init() {
	}

	public override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(PixelBuffer.ComponentType(y),
								 PixelBuffer.ComponentType(y),
								 PixelBuffer.ComponentType(y))
	}
}

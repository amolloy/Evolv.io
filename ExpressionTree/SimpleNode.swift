//
//  SimpleNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

// Conveniece class that most operators can inherit from that handles
// the standard traversal of pixels

public class SimpleNode {
	public func evaluate(width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer {
		var result = PixelBuffer(width: width, height: height)
		
		for y in 0..<height {
			for x in 0..<width {
				let fx = PixelBuffer.ComponentType(x) / PixelBuffer.ComponentType(width) - 0.5;
				let fy = PixelBuffer.ComponentType(y) / PixelBuffer.ComponentType(height) - 0.5;
				result[x, y] = evaluatePixel(x: fx, y: fy, parameters: parameters)
			}
		}
		return result
	}

	public func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		fatalError("Subclasses must override evaluatePixel")
	}
}

//
//  SimpleNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

// Conveniece class that most operators can inherit from that handles
// the standard traversal of pixels

class SimpleNode {
	func evaluate(width: Int, height: Int) -> [[Node.Value]] {
		var result = Array(
			repeating: Array(repeating: Node.Value(0, 0, 0), count: width),
			count: height
		)
		for y in 0..<height {
			for x in 0..<width {
				let fx = Float(x) / Float(width) - 0.5;
				let fy = Float(y) / Float(height) - 0.5;
				result[y][x] = evaluatePixel(x: fx, y: fy)
			}
		}
		return result
	}

	func evaluatePixel(x: Float, y: Float) -> SIMD3<Float> {
		fatalError("Subclasses must override evaluatePixel")
	}
}

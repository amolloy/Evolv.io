//
//  And.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class And: SimpleNode {
	public override init(children: [any Node]) {
		assert(children.count == 1)
		super.init(children: children)
	}

	override public var name: String {
		return "and"
	}

	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> PixelBuffer.Value {
		assert(parameters.count == 2)

		let v0 = parameters[0].sampleBilinear(at: coord)
		let v1 = parameters[1].sampleBilinear(at: coord)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			let v0b = PixelBuffer.ComponentType.toBits(v0[i])
			let v1b = PixelBuffer.ComponentType.toBits(v1[i])

			result[i] = PixelBuffer.ComponentType.fromBits(v0b & v1b)
		}

		return result
	}
}

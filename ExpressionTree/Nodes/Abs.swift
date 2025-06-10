//
//  Abs.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Abs: SimpleNode {
	public override init(children: [any Node]) {
		assert(children.count == 1)
		super.init(children: children)
	}

	override public var name: String {
		return "abs"
	}

	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> PixelBuffer.Value {
		assert(parameters.count == 1)

		let v = parameters[0].sampleBilinear(at: coord)
		return abs(v)
	}
}

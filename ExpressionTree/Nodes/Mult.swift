//
//  Mult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import simd

public class Mult: SimpleNode {
	public override init(children: [any Node]) {
		assert(children.count == 1)
		super.init(children: children)
	}

	override public var name: String {
		return "*"
	}

	public override func evaluatePixel(at coord: Tree.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> ExpressionResult.Value {
		assert(parameters.count == 2)

		let v0 = parameters[0].sampleBilinear(at: coord)
		let v1 = parameters[1].sampleBilinear(at: coord)

		return v0 * v1
	}
}

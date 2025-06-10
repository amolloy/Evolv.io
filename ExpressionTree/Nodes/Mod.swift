//
//  Mod.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Mod: SimpleNode {
	public override init(children: [any Node]) {
		assert(children.count == 1)
		super.init(children: children)
	}

	override public var name: String {
		return "mod"
	}
	
	public override func evaluatePixel(at coord: Tree.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> ExpressionResult.Value {
		assert(parameters.count == 2)
		let v0 = parameters[0].sampleBilinear(at: coord)
		let v1 = parameters[1].sampleBilinear(at: coord)
		
		let remainder = fmod(v0, v1)
		let isNegativeRemainder = remainder .< 0.0
		let positiveRemainder = remainder.replacing(with: remainder + v1, where: isNegativeRemainder)
		
		return positiveRemainder
	}
}

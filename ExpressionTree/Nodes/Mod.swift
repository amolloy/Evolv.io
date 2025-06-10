//
//  Mod.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Mod: SimpleNode {
	public init(children: [any Node]) {
		assert(children.count == 2)
		self._children = children
	}
	
	private let _children: [any Node]
	
	public override var children: [any Node] {
		return _children
	}
	
	override public var name: String {
		return "mod"
	}
	
	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		assert(parameters.count == 2)
		let v0 = parameters[0].sampleBilinear(at: coord)
		let v1 = parameters[1].sampleBilinear(at: coord)
		
		let remainder = fmod(v0, v1)
		let isNegativeRemainder = remainder .< 0.0
		let positiveRemainder = remainder.replacing(with: remainder + v1, where: isNegativeRemainder)
		
		return positiveRemainder
	}
}

//
//  Abs.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import simd

public class Abs: SimpleNode {
	public init(children: [any Node]) {
		assert(children.count == 1)
		self._children = children
	}

	private let _children: [any Node]

	public override var children: [any Node] {
		return _children
	}

	override public var name: String {
		return "abs"
	}

	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		assert(parameters.count == 1)

		let v = parameters[0].sampleBilinear(at: coord)
		return abs(v)
	}
}

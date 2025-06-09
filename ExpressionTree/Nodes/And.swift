//
//  And.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public class And: SimpleNode {
	public init(children: [any Node]) {
		assert(children.count == 2)
		self._children = children
	}

	private let _children: [any Node]

	public override var children: [any Node] {
		return _children
	}

	override public var name: String {
		return "and"
	}

	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, parameters: [PixelBuffer]) -> PixelBuffer.Value {
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

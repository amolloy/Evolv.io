//
//  BWNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

public class BWNoise: SimpleNode {
	public init(children: [any Node]) {
		assert(children.count == 2)
		self._children = children
	}

	private let _children: [any Node]

	public override var children: [any Node] {
		return _children
	}

	override public var name: String {
		return "bw-noise"
	}

	public override func evaluatePixel(x: PixelBuffer.ComponentType, y: PixelBuffer.ComponentType, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		assert(parameters.count == 2)

		let v0 = parameters[0].sampleBilinear(u: x, v: y) / 5.0
		let v1 = parameters[1].sampleBilinear(u: x, v: y)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			result[i] = Perlin.noise(x: x / v0[i], y: y / v0[i], seed: Int(v1[i]))
		}

		return result
	}
}

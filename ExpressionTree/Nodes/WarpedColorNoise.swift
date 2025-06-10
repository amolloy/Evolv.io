//
//  WarpedColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

public class WarpedColorNoise: SimpleNode {
	public init(children: [any Node]) {
		assert(children.count == 4)
		self._children = children
	}

	private let _children: [any Node]

	public override var children: [any Node] {
		return _children
	}

	override public var name: String {
		return "warped-color-noise"
	}

	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		assert(parameters.count == 4)

		let u = parameters[0].sampleBilinear(at: coord)
		let v = parameters[1].sampleBilinear(at: coord)
		let v0 = parameters[2].sampleBilinear(at: coord) * 100
		let v1 = parameters[3].sampleBilinear(at: coord)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			let sampleCoord = PixelBuffer.Coordinate(u[i], v[i])
			let scaled = sampleCoord * PixelBuffer.Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]) + i)
		}

		return result
	}
}

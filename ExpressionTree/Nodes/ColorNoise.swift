//
//  ColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

public class ColorNoise: SimpleNode {
	public override init(children: [any Node]) {
		assert(children.count == 1)
		super.init(children: children)
	}

	override public var name: String {
		return "color-noise"
	}

	override public func evaluatePixel(at coord: Tree.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> ExpressionResult.Value {
		assert(parameters.count == 2)

		let v0 = parameters[0].sampleBilinear(at: coord) * 100
		let v1 = parameters[1].sampleBilinear(at: coord)

		var result = PixelBuffer.Value(repeating: 0)
		for i in 0..<3 {
			let scaled = coord * PixelBuffer.Coordinate(repeating: v0[i])
			result[i] = Perlin.noise(at: scaled, offset: Int(v1[i]) + i)
		}

		return result
	}
}

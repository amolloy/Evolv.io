//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class Constant: SimpleNode {
	override public var name: String { "constant" }
	public let value: PixelBuffer.ComponentType
	
	public init(value: PixelBuffer.ComponentType) {
		self.value = value
	}
	
	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(repeating: value)
	}
}

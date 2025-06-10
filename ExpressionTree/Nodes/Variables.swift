//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class VariableX: SimpleNode {
	override public var name: String { "x" }
	
	public override init() {
	}
	
	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(repeating: coord.x)
	}
}

public class VariableY: SimpleNode {
	override public var name:String  { "y" }
	
	public override init() {
	}
	
	public override func evaluatePixel(at coord: PixelBuffer.Coordinate, width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		return PixelBuffer.Value(repeating: coord.y)
	}
}

//
//  SimpleNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

// Conveniece class that most operators can inherit from that handles
// the standard traversal of pixels

public class SimpleNode: MultiChildNode {
	public override var name: String {
		fatalError("subclass must override `name`")
	}
	
	public override var children: [Node] {
		[Node]()
	}
	
	typealias CT = PixelBuffer.ComponentType
	typealias Coord = PixelBuffer.Coordinate
	
	public override func evaluate(width: Int, height: Int) -> ExpressionResult {
		var result = PixelBuffer(width: width, height: height)
		
		var calculatedChildren = [ExpressionResult]()
		calculatedChildren.reserveCapacity(children.count)
		for child in children {
			calculatedChildren.append(child.evaluate(width: width, height: height))
		}
		
		for y in 0..<height {
			for x in 0..<width {
				let coord = (Coord(CT(x), CT(y)) / Coord(CT(width), CT(height))) - Coord(repeating: 0.5)
				result[x, y] = evaluatePixel(at: coord,
											 width: width,
											 height: height,
											 parameters: calculatedChildren)
			}
		}
		return result
	}
	
	public func evaluatePixel(at coord: Tree.Coordinate, width: Int, height: Int, parameters: [ExpressionResult]) -> ExpressionResult.Value {
		fatalError("Subclasses must override evaluatePixel")
	}
}

//
//  SimpleNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

// Conveniece class that most operators can inherit from that handles
// the standard traversal of pixels

public class SimpleNode: Node {
	public var name: String {
		fatalError("subclass must override `name`")
	}
	
	public var children: [Node] {
		[Node]()
	}
	
	typealias CT = PixelBuffer.ComponentType
	typealias Coord = PixelBuffer.Coordinate
	
	public func evaluate(width: Int, height: Int) -> PixelBuffer {
		var result = PixelBuffer(width: width, height: height)
		
		var calculatedChildren = [PixelBuffer]()
		calculatedChildren.reserveCapacity(children.count)
		for child in children {
			calculatedChildren.append(child.evaluate(width: width, height: height))
		}
		
		for y in 0..<height {
			for x in 0..<width {
				let coord = (Coord(CT(x), CT(y)) / Coord(CT(width), CT(height))) - Coord(repeating: 0.5)
				result[x, y] = evaluatePixel(at: coord, parameters: calculatedChildren)
			}
		}
		return result
	}
	
	public func evaluatePixel(at coord: PixelBuffer.Coordinate, parameters: [PixelBuffer]) -> PixelBuffer.Value {
		fatalError("Subclasses must override evaluatePixel")
	}
}

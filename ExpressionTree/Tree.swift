//
//  Tree.swift
//  Tree
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation

public class Tree {
	public typealias ComponentType = Double
	public typealias Value = SIMD3<ComponentType>
	public typealias Coordinate = SIMD2<ComponentType>

	let width: Int
	let height: Int
	let root: any Node

	public init(width: Int, height: Int, root: any Node) {
		self.width = width
		self.height = height
		self.root = root
	}

	public func evaluate() -> PixelBuffer {
		return root.evaluate(width: width, height: height) as! PixelBuffer
	}
}

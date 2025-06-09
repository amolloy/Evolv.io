//
//  Tree.swift
//  Tree
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation

public class Tree {
	let width: Int
	let height: Int
	let root: any Node

	public init(width: Int, height: Int, root: any Node) {
		self.width = width
		self.height = height
		self.root = root
	}

	public func evaluate() -> PixelBuffer {
		return root.evaluate(width: width, height: height, parameters: [])
	}
}

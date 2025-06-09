//
//  Operator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public protocol Node {
	var name: String { get }
	func evaluate(width: Int, height: Int, parameters: [PixelBuffer]) -> PixelBuffer
}

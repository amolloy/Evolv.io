//
//  ExpressionResult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public protocol ExpressionResult {
	typealias Value = Tree.Value
	subscript(x: Int, y: Int) -> Value { get }
	func sampleBilinear(at coord: Tree.Coordinate) -> Value
}

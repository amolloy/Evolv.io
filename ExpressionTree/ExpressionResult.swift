//
//  ExpressionResult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public protocol ExpressionResult {
	typealias Value = Tree.Value
	typealias Coordinate = Tree.Coordinate

	func sampleBilinear(at coord: Coordinate) -> Value
}

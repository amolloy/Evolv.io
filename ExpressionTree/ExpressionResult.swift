//
//  ExpressionResult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public protocol ExpressionResult {
	func sampleBilinear(at coord: Coordinate) -> Value
}

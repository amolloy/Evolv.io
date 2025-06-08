//
//  Operator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

protocol Node {
	typealias Value = SIMD3<Float>

	var name: String { get }
	func evaluate(width: Int, height: Int) -> [[Value]]
}

//
//  Operator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public protocol Node {
	var name: String { get }
	var children: [Node] { get }

	func evaluate(using evaluator: Evaluator) -> any ExpressionResult
}

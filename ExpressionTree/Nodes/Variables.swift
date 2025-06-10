//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class VariableX: Node {
	public var name: String { "x" }
	public var children: [any Node] = []
	public init() {}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return VariableXValue(evaluator: evaluator)
	}
}

struct VariableXValue: ExpressionResult {
	typealias CT = Tree.ComponentType

	let evaluator: Evaluator

	func sampleBilinear(at coord: Coordinate) -> Value {
		return Value(repeating: coord.x)
	}
}

public class VariableY: Node {
	public var name: String { "y" }
	public var children: [any Node] = []
	public init() {}
	
	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return VariableYValue(evaluator: evaluator)
	}
}

struct VariableYValue: ExpressionResult {
	typealias CT = Tree.ComponentType

	let evaluator: Evaluator

	func sampleBilinear(at coord: Coordinate) -> Value {
		return Value(repeating: coord.y)
	}
}

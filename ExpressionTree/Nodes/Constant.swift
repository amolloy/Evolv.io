//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class Constant: Node {
	public static var name: String {
		"constant"
	}

	public var children: [any Node] = []
	public let value: Tree.ComponentType

	required public init(_ children: [Node]) {
		value = 0.0
	}

	public init(_ value: Tree.ComponentType) {
		self.value = value
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return ConstantResult(self.value)
	}

	public func toString() -> String {
		return "\(value)"
	}
}

struct ConstantResult : ExpressionResult {
	let value: Value

	init(_ value: Tree.ComponentType) {
		self.value = Value(repeating: value)
	}

	public func sampleBilinear(at coord: Tree.Coordinate) -> Value {
		return value
	}
}

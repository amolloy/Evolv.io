//
//  ConstantTriplet.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class ConstantTriplet: Node {
	public static var name: String {
		"triplet-constant"
	}

	public var children: [any Node] = []
	public let value: Value

	required public init(_ children: [Node]) {
		value = Value(repeating: 0)
	}

	public init(_ value: Value) {
		self.value = value
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return ConstantTripletResult(self.value)
	}

	public func toString() -> String {
		return "#(\(value.x) \(value.y) \(value.z))"
	}
}

struct ConstantTripletResult : ExpressionResult {
	let value: Value

	init(_ value: Value) {
		self.value = value
	}

	public func sampleBilinear(at coord: Coordinate) -> Value {
		return value
	}
}

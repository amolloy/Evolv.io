//
//  TripletConstant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class TripletConstant: Node {
	public static var name: String {
		"triplet-constant"
	}

	public var children: [any Node] = []
	public let value: Tree.Value

	required public init(_ children: [Node]) {
		value = Tree.Value(repeating: 0)
	}

	public init(_ value: Tree.Value) {
		self.value = value
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		return TripletConstantResult(self.value)
	}

	public func toString() -> String {
		return "#(\(value.x) \(value.y) \(value.z))"
	}
}

struct TripletConstantResult : ExpressionResult {
	let value: Value

	init(_ value: Tree.Value) {
		self.value = value
	}

	public func sampleBilinear(at coord: Tree.Coordinate) -> Value {
		return value
	}
}

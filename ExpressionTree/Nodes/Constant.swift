//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class Constant: SimpleNode {
	public let value: Tree.ComponentType
	public override var name: String {
		get { "\(value)" }
	}

	public init(value: Tree.ComponentType) {
		self.value = value
		super.init(children: [])
	}

	public override func evaluate(width: Int, height: Int) -> any ExpressionResult {
		return ConstantResult(value)
	}
}

struct ConstantResult : ExpressionResult {
	let value: Value

	init(_ value: Tree.ComponentType) {
		self.value = Value(repeating: value)
	}

	public subscript(x: Int, y: Int) -> Value {
		return value
	}

	public func sampleBilinear(at coord: Tree.Coordinate) -> Value {
		return value
	}
}

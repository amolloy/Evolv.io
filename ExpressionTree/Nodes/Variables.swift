//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class VariableX: SimpleNode {
	public init() {
		super.init(children: [])
	}

	public override var name: String { "x" }

	public override func evaluate(width: Int, height: Int) -> any ExpressionResult {
		return VariableXValue(size: width)
	}
}

struct VariableXValue: ExpressionResult {
	typealias CT = Tree.ComponentType

	let size: Int

	init(size: Int) {
		self.size = size
	}

	subscript(x: Int, y: Int) -> Value {
		return Value(repeating: CT(x) / CT(size))
	}
	
	func sampleBilinear(at coord: Tree.Coordinate) -> Value {
		return Value(repeating: coord.x)
	}
}

public class VariableY: SimpleNode {
	public init() {
		super.init(children: [])
	}

	public override var name: String { "y" }

	public override func evaluate(width: Int, height: Int) -> any ExpressionResult {
		return VariableYValue(size: height)
	}
}

struct VariableYValue: ExpressionResult {
	typealias CT = Tree.ComponentType

	let size: Int

	init(size: Int) {
		self.size = size
	}

	subscript(x: Int, y: Int) -> Value {
		return Value(repeating: CT(y) / CT(size))
	}

	func sampleBilinear(at coord: Tree.Coordinate) -> Value {
		return Value(repeating: coord.y)
	}
}

//
//  Round.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class Round: Node {
	public static var name: String {
		return "round"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		let v0 = children[0].codegenMSL(into: context)
		let v1 = children[1].codegenMSL(into: context)
		// rint (round-to-nearest-even) matches Swift's .rounded(.toNearestOrEven),
		// unlike MSL's round() which rounds ties away from zero.
		let q = context.declare("rint(\(v0.variableName) / \(v1.variableName))")
		return "\(q.variableName) * \(v1.variableName)"
	}
}

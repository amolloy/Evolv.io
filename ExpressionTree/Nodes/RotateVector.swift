//
//  RotateVector.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

public final class RotateVector: Node {
	public static var name: String {
		return "rotate-vector"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 3)
		let angle = children[0].codegenMSL(into: context)
		let x = children[1].codegenMSL(into: context)
		let y = children[2].codegenMSL(into: context)
		let c = context.declare("cos(\(angle.variableName) * M_PI_F)")
		let s = context.declare("sin(\(angle.variableName) * M_PI_F)")
		return "\(c.variableName) * \(x.variableName) + \(s.variableName) * \(y.variableName)"
	}
}

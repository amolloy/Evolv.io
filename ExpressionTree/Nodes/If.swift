//
//  If.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class If: Node {
	public static var name: String {
		return "if"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 3)
		let condition = children[0].codegenMSL(into: context)
		let thenVal = children[1].codegenMSL(into: context)
		let elseVal = children[2].codegenMSL(into: context)
		return "select(\(elseVal.variableName), \(thenVal.variableName), \(condition.variableName) > float3(0.0))"
	}
}

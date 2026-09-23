//
//  Mult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public class Mult: Node {
	public static var name: String {
		return "*"
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
		return "\(v0.variableName) * \(v1.variableName)"
	}
}

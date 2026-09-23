//
//  Dissolve.swift
//  Evolv.io
//
//  Created by Andy Molloy on 8/27/26.
//

public class Dissolve: Node {
	public static var name: String {
		return "dissolve"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 3)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 3)
		let v0 = children[0].codegenMSL(into: context)
		let w = children[1].codegenMSL(into: context)
		let v1 = children[2].codegenMSL(into: context)
		return "(float3(1.0) - \(w.variableName)) * \(v0.variableName) + \(w.variableName) * \(v1.variableName)"
	}
}

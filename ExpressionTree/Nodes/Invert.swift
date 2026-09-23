//
//  Invert.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class Invert: Node {
	public static var name: String {
		return "invert"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 1)
		let e = children[0].codegenMSL(into: context)
		return "float3(1.0) - \(e.variableName)"
	}
}

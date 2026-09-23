//
//  Mod.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class Mod: Node {
	public static var name: String {
		return "mod"
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

		let isZeroMask = context.declare("\(v1.variableName) == float3(0.0)", type: "bool3")
		let safeDivisor = context.declare("select(\(v1.variableName), float3(1.0), \(isZeroMask.variableName))")
		let remainder = context.declare("fmod(\(v0.variableName), \(safeDivisor.variableName))")
		let isNegativeRemainder = context.declare("\(remainder.variableName) < float3(0.0)", type: "bool3")
		return "select(\(remainder.variableName), \(remainder.variableName) + \(v1.variableName), \(isNegativeRemainder.variableName))"
	}
}

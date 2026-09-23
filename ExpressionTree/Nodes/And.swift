//
//  And.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

public class And: Node {
	public static var name: String {
		return "and"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	// Bitwise AND on raw IEEE-754 bit patterns, ported at 32-bit (float)
	// width instead of the CPU's 64-bit (double) width -- a real semantic
	// difference (different exponent/mantissa layout), not just precision
	// loss, accepted per the Metal codegen migration plan. Parity tests for
	// this node used a looser tolerance for that reason.
	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		let v0 = children[0].codegenMSL(into: context)
		let v1 = children[1].codegenMSL(into: context)
		let bits0 = context.declare("as_type<uint3>(\(v0.variableName))", type: "uint3")
		let bits1 = context.declare("as_type<uint3>(\(v1.variableName))", type: "uint3")
		let resultBits = context.declare("\(bits0.variableName) & \(bits1.variableName)", type: "uint3")
		return "as_type<float3>(\(resultBits.variableName))"
	}
}

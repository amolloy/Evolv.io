//
//  Log.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public class Log: Node {
	public static var name: String {
		return "log"
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
		let numerator = context.declare("log(abs(\(v0.variableName)))")
		let denominator = context.declare("log(abs(\(v1.variableName)))")
		let result = context.declare("\(numerator.variableName) / \(denominator.variableName)")
		return "select(\(result.variableName), float3(0.0), isnan(\(result.variableName)))"
	}
}

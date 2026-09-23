//
//  WarpedBWNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 8/27/26.
//

public class WarpedBWNoise: Node {
	public static var name: String {
		return "warped-bw-noise"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 4)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 4)
		context.require(.perlinTable)
		let u = children[0].codegenMSL(into: context)
		let v = children[1].codegenMSL(into: context)
		let e2 = children[2].codegenMSL(into: context)
		let e3 = children[3].codegenMSL(into: context)
		let v0 = context.declare("\(e2.variableName) * 50.0")
		return "float3(perlinNoise(float2(\(u.variableName).x, \(v.variableName).x) * \(v0.variableName).x, int(\(e3.variableName).x)), " +
			   "perlinNoise(float2(\(u.variableName).y, \(v.variableName).y) * \(v0.variableName).y, int(\(e3.variableName).y)), " +
			   "perlinNoise(float2(\(u.variableName).z, \(v.variableName).z) * \(v0.variableName).z, int(\(e3.variableName).z)))"
	}
}

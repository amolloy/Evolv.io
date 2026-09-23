//
//  ColorNoise.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

public class ColorNoise: Node {
	public static var name: String {
		return "color-noise"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 2)
		context.require(.perlinTable)
		let e0 = children[0].codegenMSL(into: context)
		let e1 = children[1].codegenMSL(into: context)
		let v0 = context.declare("\(e0.variableName) * 50.0")
		return "float3(perlinNoise(coord * \(v0.variableName).x, int(\(e1.variableName).x) + 0), " +
			   "perlinNoise(coord * \(v0.variableName).y, int(\(e1.variableName).y) + 1), " +
			   "perlinNoise(coord * \(v0.variableName).z, int(\(e1.variableName).z) + 2))"
	}
}

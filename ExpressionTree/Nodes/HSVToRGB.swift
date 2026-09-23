//
//  HSVToRGB.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

public class HSVToRGB: Node {
	public static var name: String {
		return "hsv-to-rgb"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 1)
		self.children = children
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		assert(children.count == 1)
		let hsv = children[0].codegenMSL(into: context)
		let h = context.declare("fmod(\(hsv.variableName).x, 1.0) * 6.0", type: "float")
		let s = context.declare("\(hsv.variableName).y", type: "float")
		let v = context.declare("\(hsv.variableName).z", type: "float")
		let c = context.declare("\(v.variableName) * \(s.variableName)", type: "float")
		let x = context.declare("\(c.variableName) * (1.0 - abs(fmod(\(h.variableName), 2.0) - 1.0))", type: "float")
		let m = context.declare("\(v.variableName) - \(c.variableName)", type: "float")

		let rgb = context.declare("""
		(int(\(h.variableName)) == 0) ? float3(\(c.variableName), \(x.variableName), 0.0) : \
		(int(\(h.variableName)) == 1) ? float3(\(x.variableName), \(c.variableName), 0.0) : \
		(int(\(h.variableName)) == 2) ? float3(0.0, \(c.variableName), \(x.variableName)) : \
		(int(\(h.variableName)) == 3) ? float3(0.0, \(x.variableName), \(c.variableName)) : \
		(int(\(h.variableName)) == 4) ? float3(\(x.variableName), 0.0, \(c.variableName)) : \
		(int(\(h.variableName)) == 5) ? float3(\(c.variableName), 0.0, \(x.variableName)) : \
		float3(0.0, 0.0, 0.0)
		""")

		return "\(rgb.variableName) + float3(\(m.variableName))"
	}
}

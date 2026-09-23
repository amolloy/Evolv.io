//
//  Variables.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class VariableX: Node {
	public static var name: String { "x" }
	public var children: [any Node] = []
	required public init(_ children: [any Node] = []) {}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		"float3(coord.x)"
	}
}

public class VariableY: Node {
	public static var name: String { "y" }
	public var children: [any Node] = []
	required public init(_ children: [any Node] = []) {}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		"float3(coord.y)"
	}
}

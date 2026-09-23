//
//  Constant.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public class Constant: Node {
	public static var name: String {
		"constant"
	}

	public var children: [any Node] = []
	public let value: ComponentType

	required public init(_ children: [any Node]) {
		value = 0.0
	}

	public init(_ value: ComponentType) {
		self.value = value
	}

	public func toString() -> String {
		return "\(value)"
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		"float3(\(mslFloatLiteral(value)))"
	}
}

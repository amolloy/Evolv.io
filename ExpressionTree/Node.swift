//
//  Operator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public protocol Node: Identifiable where ID == ObjectIdentifier {
	static var name: String { get }
	var children: [any Node] { get }

	init(_ children: [any Node]) throws

	func toString() -> String

	/// Emits this node's MSL expression as raw text (e.g. `"v0 + v1"`), given
	/// that `context` already holds emitted variable names for `children`
	/// (fetched via `children[i].codegenMSL(into:)`, not this method directly).
	/// Called once per node during codegen -- once per distinct tree shape,
	/// producing the MSL text a compiled kernel then runs per pixel on the GPU.
	func _emitMSL(into context: MSLCodegenContext) -> String
}

public extension Node {
	/// The dispatch entry point callers should use: emits (or reuses a
	/// memoized emission of) this node's MSL expression as a fresh local
	/// variable. Dedups by node identity -- this matters whenever the same
	/// node instance is referenced more than once (e.g. `ColorGradient`'s
	/// synthesized `ScaledResult`-style wrappers all sharing one `p3`
	/// sub-expression), not just for tidiness.
	func codegenMSL(into context: MSLCodegenContext) -> MSLValue {
		context.emit(for: self) { self._emitMSL(into: context) }
	}
}

public extension Node {
	func toString() -> String {
		let hasChildren = children.count > 0

		var str = ""
		if hasChildren {
			str += "("
		}

		str += "\(Self.name)"
		if hasChildren {
			let childStrings = children.map { $0.toString() }
			str += " \(childStrings.joined(separator: " "))"
			str += ")"
		}

		return str
	}
}

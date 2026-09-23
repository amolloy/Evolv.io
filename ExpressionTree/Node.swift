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
	
	func evaluate(using evaluator: Evaluator) -> any ExpressionResult
	func toString() -> String

	func debugValues(using evaluator: Evaluator,
					 at coord: Coordinate) -> [String: String]

	/// Emits this node's MSL expression as raw text (e.g. `"v0 + v1"`), given
	/// that `context` already holds emitted variable names for `children`
	/// (fetched via `children[i].codegenMSL(into:)`, not this method directly).
	/// Called once per node during codegen -- the direct analog of
	/// `_evaluate(using:)`'s "called once during graph construction" role,
	/// just producing MSL text instead of a runtime `ExpressionResult`.
	///
	/// Defaults to a `fatalError` (see below) so every existing node type
	/// keeps compiling untouched until it's ported one at a time; this default
	/// should never be reached once the Metal migration is complete.
	func _emitMSL(into context: MSLCodegenContext) -> String
}

public extension Node {
	func _emitMSL(into context: MSLCodegenContext) -> String {
		fatalError("\(Self.name) has not been ported to Metal codegen yet")
	}

	/// The dispatch entry point callers should use: emits (or reuses a
	/// memoized emission of) this node's MSL expression as a fresh local
	/// variable. Mirrors `CachedNode`'s runtime cache, but at codegen time
	/// and applied uniformly to every node instead of opt-in per type --
	/// this matters whenever the same node instance is referenced more than
	/// once (e.g. `ColorGradient`'s synthesized `ScaledResult` wrappers all
	/// sharing one `p3` sub-expression), not just for tidiness.
	func codegenMSL(into context: MSLCodegenContext) -> MSLValue {
		context.emit(for: self.id) { self._emitMSL(into: context) }
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

public extension Node {
	func debugValues(using evaluator: Evaluator,
					 at coord: Coordinate) -> [String: String] {
		return [:]  // default: nothing to show
	}
}

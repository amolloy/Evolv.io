//
//  NodeRegistry.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import Foundation

public final class NodeRegistry {
	public typealias NodeConstructor = ([any Node]) throws -> any Node

	/// The shared, reloadable registry every `Parser` uses -- a singleton
	/// (like `MetalRenderContext.shared`) rather than one-per-`Parser`
	/// specifically so `reload()` (see below) is visible everywhere at once.
	public static let shared = NodeRegistry()

	// Everything is DSL-defined now (see Evolv.io/Resources/
	// BundledNodes/*.evolvnode) except these two, which can't become
	// .evolvnode files at all -- they're literal syntax the Lisp tokenizer
	// recognizes directly (a bare number, `#(...)`), never a name+children
	// shape passed through `registry.makeNode`, so there's no "body" a DSL
	// file could write.
	private static let builtinNodeTypes: [any Node.Type] = [
		Constant.self,
		ConstantTriplet.self,
	]

	public private(set) var registry: [String: NodeConstructor]
	/// Whatever went wrong on the most recent load/reload -- a bad or
	/// colliding `.evolvnode` file is logged here (and to the console, see
	/// `reload()`) rather than crashing the app; see `DSLLibrary.scan`.
	public private(set) var loadIssues: [DSLLoadIssue]

	public init() {
		let result = Self.buildRegistry()
		registry = result.registry
		loadIssues = result.issues
		Self.logIssues(loadIssues)
	}

	/// Re-scans the bundled + user Nodes folders and rebuilds the registry
	/// in place -- lets "Reload Custom Nodes" pick up filesystem changes
	/// without relaunching the app. Also clears MetalRenderContext's
	/// pipeline cache -- a DSL node's cache key (its `toString()`) doesn't
	/// encode a required module's *content*, so without this an edited
	/// module file could still serve a stale compiled kernel after reload.
	public func reload() {
		let result = Self.buildRegistry()
		registry = result.registry
		loadIssues = result.issues
		Self.logIssues(loadIssues)
		MetalRenderContext.shared.clearPipelineCache()
	}

	private static func buildRegistry() -> (registry: [String: NodeConstructor], issues: [DSLLoadIssue]) {
		// Programmatically build the registry from the list of types.
		// No giant switch statement needed!
		var builtRegistry: [String: NodeConstructor] = [:]
		for type in builtinNodeTypes {
			builtRegistry[type.name] = type.init
		}

		// DSL-defined nodes (see ExpressionTree/DSL/) layer on top: scanned
		// from the app-bundled node library and the user's editable Nodes
		// folder. A `.evolvnode` file claiming a name already used by a
		// built-in above is a load issue, not a silent override -- see
		// DSLLibrary.scan's `reservedNames`.
		let (dslConstructors, issues) = DSLLibrary.scan(
			roots: DSLLibrary.productionRoots,
			reservedNames: Set(builtinNodeTypes.map { $0.name })
		)
		builtRegistry.merge(dslConstructors) { existing, _ in existing }

		return (builtRegistry, issues)
	}

	private static func logIssues(_ issues: [DSLLoadIssue]) {
		for issue in issues {
			print("DSL load issue (\(issue.fileURL.lastPathComponent)): \(issue.message)")
		}
	}

	public func makeNode(name: String, children: [any Node], expression: String) throws(ParseError) -> any Node {
        guard let constructor = registry[name] else {
            throw ParseError.unknownFunction(name: name, expression: expression)
        }
        do {
            return try constructor(children)
        } catch {
            // `NodeConstructor` is declared as a plain `throws` closure --
            // it can throw a `ParseError` itself (e.g. `.invalidArgumentCount`
            // from `DSLCodegenNode`) or something unrelated entirely, so
            // everything gets wrapped here to keep `Parser` on a single,
            // typed error path regardless of which.
            throw ParseError.nodeConstructionFailed(name: name, expression: expression, underlying: error)
        }
    }
}

/// Everything `Parser` (and the registry it drives) can throw while turning
/// Lisp-like text into a `Node` tree. Every case carries the full source
/// `expression` plus whatever was actually found, so `errorDescription` is
/// enough on its own for a user to locate and fix the mistake -- see
/// `Parser`'s centralized logging of this at the top-level `parse(_:)`.
public enum ParseError: Error, LocalizedError {
	case unexpectedEndOfInput(expression: String, expected: String)
	case unknownFunction(name: String, expression: String)
	case invalidNumberLiteral(token: String, expression: String, context: String)
	case expectedClosingParenthesis(expression: String, found: String)
	case invalidArgumentCount(name: String, expected: Int, found: Int)
	case nodeConstructionFailed(name: String, expression: String, underlying: Error)

	public var errorDescription: String? {
		switch self {
			case .unexpectedEndOfInput(let expression, let expected):
				return "Unexpected end of expression \"\(expression)\": expected \(expected)."
			case .unknownFunction(let name, let expression):
				return "Unknown function name '\(name)' in expression \"\(expression)\"."
			case .invalidNumberLiteral(let token, let expression, let context):
				return "Invalid number '\(token)' in expression \"\(expression)\" (\(context))."
			case .expectedClosingParenthesis(let expression, let found):
				return "Expected a closing ')' in expression \"\(expression)\", but found \(found)."
			case .invalidArgumentCount(let name, let expected, let found):
				return "'\(name)' expects \(expected) argument\(expected == 1 ? "" : "s"), but found \(found)."
			case .nodeConstructionFailed(let name, let expression, let underlying):
				return "Failed to construct node '\(name)' in expression \"\(expression)\": \(underlying.localizedDescription)"
		}
	}
}

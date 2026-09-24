//
//  NodeRegistry.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//


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

	public func makeNode(name: String, children: [any Node]) throws -> any Node {
        guard let constructor = registry[name] else {
            throw ParseError.unknownFunction(name)
        }
        return try constructor(children)
    }
}

public enum ParseError: Error {
	case unexpectedEndOfInput
	case unknownFunction(String)
	case invalidToken(String)
	case expectedClosingParenthesis
	case invalidArgumentCount(expected: Int, found: Int)

	public var errorDescription: String? {
		switch self {
			case .unexpectedEndOfInput:
				return "Unexpected end of expression."
			case .unknownFunction(let name):
				return "Unknown function name: '\(name)'."
			case .invalidToken(let token):
				return "Invalid token found: '\(token)'."
			case .expectedClosingParenthesis:
				return "Expected a closing ')'."
			case .invalidArgumentCount(let expected, let found):
				return "Invalid argument count for function: expected \(expected), but found \(found)."
		}
	}
}

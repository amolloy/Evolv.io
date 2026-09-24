//
//  DSLCodegenNode.swift
//  Evolv.io
//
//  Spike: a generic `Node` that emits MSL by interpreting a parsed
//  DSLTemplate against an MSLCodegenContext, instead of a hand-written
//  Swift `_emitMSL`. This exists to answer a design question -- "would a
//  readable text format for these definitions actually work, including the
//  hard cases?" -- not to be wired into NodeRegistry/production rendering
//  yet. See ExpressionTreeTests' DSLSpikeTests for the parity checks this
//  is validated against (same golden values as the hand-written Mod/
//  ColorGradient tests).
//
//  Every DSL-defined node "type" (mod, color-grad, whatever comes next)
//  is the same Swift class here, parameterized by a DSLTemplate instance
//  rather than being its own Node conformer -- that's the whole point
//  (definitions become data, loadable/reloadable at runtime, instead of
//  requiring a recompile). It does mean `Node.name` (a *static*
//  requirement, appropriate when one Swift type == one node type) doesn't
//  fit: this class overrides `toString()` directly to use the template's
//  name instead of ever consulting `Self.name`, and gives that static
//  requirement an unused placeholder value. Reworking `Node.name` into an
//  instance property so DSLCodegenNode could report a real per-template
//  name (needed once these are registered in NodeRegistry and rendered
//  through the production pipeline-cache path, which keys on
//  `node.toString()`) is next-phase work, not needed to prove this out.
//

public final class DSLCodegenNode: Node {
	public static var name: String { "dsl" }

	public let template: DSLTemplate
	public let params: [String: DSLParamValue]
	public var children: [any Node]

	public init(template: DSLTemplate, params: [String: DSLParamValue] = [:], children: [any Node]) {
		precondition(children.count == template.params.count,
					 "'\(template.name)' expects \(template.params.count) children, got \(children.count)")
		self.template = template
		self.params = params
		self.children = children
	}

	public init(_ children: [any Node]) throws {
		fatalError("DSLCodegenNode has no fixed arity -- construct with init(template:params:children:) instead")
	}

	public func toString() -> String {
		guard !children.isEmpty else { return template.name }
		return "(\(template.name) \(children.map { $0.toString() }.joined(separator: " ")))"
	}

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		for requirement in template.requires {
			switch requirement {
				case "lighting": context.require(.lightingHelpers)
				case "perlin": context.require(.perlinTable)
				default: preconditionFailure("'\(template.name)': unknown requires(\(requirement))")
			}
		}

		var env: [String: DSLBinding] = ["coord": .literal("coord")]
		for (decl, child) in zip(template.params, children) {
			if decl.isFunction {
				env[decl.name] = .function(context.emitFunction(for: child))
			} else {
				env[decl.name] = .value(child.codegenMSL(into: context))
			}
		}

		let interpreter = DSLInterpreter(context: context, params: params, env: env)
		for stmt in template.body {
			interpreter.execute(stmt)
		}
		return interpreter.evaluate(template.returnExpr)
	}
}

/// What a DSL name currently refers to while interpreting a template's body.
enum DSLBinding {
	/// An already-`declare`d MSL local -- referencing it by name just
	/// substitutes its variable name.
	case value(MSLValue)
	/// Verbatim substitution text -- used for `$param`s (formatted once as
	/// an MSL literal) and for a reduction loop's induction variable
	/// (formatted as a plain integer at codegen-unroll time).
	case literal(String)
	/// A child sampled via `MSLCodegenContext.emitFunction` -- referencing
	/// it bare would be meaningless in MSL (there's no such thing as a
	/// function value), but calling it (`source(coord + ...)`) substitutes
	/// the generated function's name as the callee.
	case function(String)

	var text: String {
		switch self {
			case .value(let v): return v.variableName
			case .literal(let s): return s
			case .function(let s): return s
		}
	}
}

/// Walks a DSLTemplate's statements/expression against one MSLCodegenContext,
/// translating each into the same `context.declare(...)` calls a hand-written
/// `_emitMSL` would make directly.
final class DSLInterpreter {
	private let context: MSLCodegenContext
	private let params: [String: DSLParamValue]
	private var env: [String: DSLBinding]

	init(context: MSLCodegenContext, params: [String: DSLParamValue], env: [String: DSLBinding]) {
		self.context = context
		self.params = params
		self.env = env
	}

	func execute(_ stmt: DSLLetStmt) {
		let text = evaluate(stmt.value)
		env[stmt.name] = .value(context.declare(text, type: stmt.type ?? "float3"))
	}

	func evaluate(_ expr: DSLExpr) -> String {
		switch expr {
			case .number(let text):
				return text

			case .identifier(let name):
				guard let binding = env[name] else {
					preconditionFailure("DSL: unresolved identifier '\(name)'")
				}
				return binding.text

			case .param(let name):
				guard let value = params[name] else {
					preconditionFailure("DSL: unresolved param '$\(name)'")
				}
				switch value {
					case .float(let f): return mslFloatLiteral(f)
					case .int(let i): return String(i)
				}

			case .unary(let op, let operand):
				return "(\(op)\(evaluate(operand)))"

			case .binary(let op, let lhs, let rhs):
				return "(\(evaluate(lhs)) \(op) \(evaluate(rhs)))"

			case .ternary(let cond, let then, let else_):
				return "(\(evaluate(cond)) ? \(evaluate(then)) : \(evaluate(else_)))"

			case .member(let base, let name):
				return "\(evaluate(base)).\(name)"

			case .call(let callee, let args):
				let argsText = args.map { evaluate($0) }.joined(separator: ", ")
				// A bound identifier (a sampled child, most commonly) calls
				// through its binding's text (the emitted function's name).
				// An *unbound* identifier is assumed to be a passthrough MSL
				// builtin/helper name (`float3`, `select`, `avgLum`, ...) --
				// used verbatim as the callee text, not run back through
				// `evaluate` (which would reject it: the generic .identifier
				// case below requires a binding, precisely because a bare
				// *non-call* reference to an unbound name is never valid).
				if case .identifier(let name) = callee {
					if let binding = env[name] {
						return "\(binding.text)(\(argsText))"
					}
					return "\(name)(\(argsText))"
				}
				return "\(evaluate(callee))(\(argsText))"

			case .reduce(let variable, let lo, let hi, let body, let result):
				return evaluateReduce(variable: variable, lo: lo, hi: hi, body: body, result: result)
		}
	}

	/// Unrolls `average(variable in lo...hi) { body; result }` at codegen
	/// time (not as a runtime MSL loop) into `lo...hi` independently-scoped
	/// copies of `body`/`result`, then averages their results -- the DSL
	/// equivalent of ColorGradient's Swift-side per-tap loop.
	private func evaluateReduce(variable: String, lo: DSLExpr, hi: DSLExpr, body: [DSLLetStmt], result: DSLExpr) -> String {
		let loValue = resolveInt(lo)
		let hiValue = resolveInt(hi)
		precondition(loValue <= hiValue, "DSL: empty reduce range \(loValue)...\(hiValue)")

		var terms: [String] = []
		for i in loValue...hiValue {
			var iterEnv = env
			iterEnv[variable] = .literal(String(i))
			let iteration = DSLInterpreter(context: context, params: params, env: iterEnv)
			for stmt in body {
				iteration.execute(stmt)
			}
			terms.append(iteration.evaluate(result))
		}
		let count = mslFloatLiteral(ComponentType(hiValue - loValue + 1))
		return "((\(terms.joined(separator: " + "))) / \(count))"
	}

	private func resolveInt(_ expr: DSLExpr) -> Int {
		switch expr {
			case .number(let text):
				guard let i = Int(text) else {
					preconditionFailure("DSL: expected an integer literal in a reduce range, got '\(text)'")
				}
				return i
			case .param(let name):
				guard case .int(let i)? = params[name] else {
					preconditionFailure("DSL: expected an int param '$\(name)' in a reduce range")
				}
				return i
			default:
				preconditionFailure("DSL: reduce range bounds must be integer literals or int params")
		}
	}
}

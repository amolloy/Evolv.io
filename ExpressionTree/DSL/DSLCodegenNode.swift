//
//  DSLCodegenNode.swift
//  Evolv.io
//
//  A generic `Node` that emits MSL by interpreting a parsed DSLTemplate
//  against an MSLCodegenContext, instead of a hand-written Swift
//  `_emitMSL`. See DSLLibrary.swift for how these get constructed from
//  scanned `.evolvnode` files, and ExpressionTreeTests' DSLSpikeTests/
//  DSLLibraryTests for the parity checks this is validated against.
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
//  name is a bigger protocol change than this library needs to solve.
//

public final class DSLCodegenNode: Node {
	public static var name: String { "dsl" }

	public let template: DSLTemplate
	public let params: [String: DSLParamValue]
	/// Modules this node's `requires()` clause can resolve against, already
	/// namespace-resolved by whoever constructed this (see
	/// `DSLLibrary.scan`) but not yet turned into MSL text -- that happens
	/// lazily in `_emitMSL`, only when actually rendered, so a bug in an
	/// unused module can never crash anything that doesn't call it (same
	/// deferred-until-rendered behavior as a bug in a node's own body).
	let modules: [String: DSLResolvedModule]
	public var children: [any Node]

	public init(template: DSLTemplate, params: [String: DSLParamValue] = [:], modules: [String: DSLResolvedModule] = [:], children: [any Node]) throws {
		guard children.count == template.params.count else {
			throw ParseError.invalidArgumentCount(name: template.name, expected: template.params.count, found: children.count)
		}
		self.template = template
		self.params = params
		self.modules = modules
		self.children = children
	}

	public init(_ children: [any Node]) throws {
		fatalError("DSLCodegenNode has no fixed arity -- construct with init(template:params:modules:children:) instead")
	}

	public func toString() -> String {
		guard !children.isEmpty else { return template.name }
		return "(\(template.name) \(children.map { $0.toString() }.joined(separator: " ")))"
	}

	/// Overrides the `Self.name`-based default (always the fixed "dsl"
	/// placeholder for this class) with the real per-file name -- see
	/// `Node.displayName`'s doc comment for why this needs to be an
	/// instance property at all.
	public var displayName: String { template.name }

	public func _emitMSL(into context: MSLCodegenContext) -> String {
		// External params win over a node's own `param $name = default` --
		// see DSLTemplate.paramDefaults.
		let effectiveParams = template.paramDefaults.merging(params) { _, external in external }

		var env: [String: DSLBinding] = ["coord": .literal("coord")]

		for requirement in template.requires {
			if requirement == "perlin" {
				// The one reserved intrinsic: its table is live-shuffled
				// Swift data (see Perlin.swift), so it can never be a
				// plain text module like everything else here.
				context.require(.perlinTable)
				continue
			}
			guard let resolved = modules[requirement] else {
				preconditionFailure("'\(template.name)': unresolved requires(\(requirement)) -- no such module")
			}
			// Every function this module defines gets emitted under a
			// name-mangled prefix (derived from its *qualified* name, not
			// the bare `requirement` text -- see DSLResolvedModule) and
			// bound here so this node's own body can still call it by its
			// plain name. That mangling is what makes this collision-proof:
			// two independently-authored modules that both happen to
			// define "avgLum" can never produce two MSL functions with
			// the same name in one kernel, however many end up required
			// by one tree. This is a real bug that happened before
			// mangling existed: Figure 10 combines `bump` (back then a
			// hand-written node pulling in a fixed intrinsic lighting
			// preamble) with `color-grad` (required a separately-text
			// "lighting" module defining the exact same three names) --
			// "redefinition of 'avgLum'" from Metal. `bump` is a DSL node
			// requiring this same real module now, but the mangling still
			// matters: nothing stops two *different* third-party modules
			// from colliding on a common helper name like this.
			let prefix = mslModulePrefix(for: resolved.qualifiedName)
			context.requireModule(name: resolved.qualifiedName, text: emitModuleFunctionsMSL(resolved, prefix: prefix))
			for funcDecl in resolved.module.funcs {
				env[funcDecl.name] = .function(prefix + funcDecl.name)
			}
		}

		// A `fn taps(...)` child is emitted inside a tap scope, so any tap
		// cache inside it knows these taps reach it (see `registerTapCache`).
		var tapScopes: [String: Int] = [:]
		for (decl, child) in zip(template.params, children) {
			if decl.isFunction {
				let tapScope = decl.taps != nil ? context.beginTapScope() : nil
				env[decl.name] = .sampledFunction(context.emitFunction(for: child))
				if let tapScope {
					context.endTapScope()
					tapScopes[decl.name] = tapScope
				}
			} else {
				env[decl.name] = .value(child.codegenMSL(into: context))
			}
		}

		// A `debug`-annotated `$param` reads from the live `debugValues`
		// uniform instead of getting baked in as a literal -- see
		// MSLCodegenContext.registerDebugControl. Every other `$param`
		// (i.e. every non-debug param today) is completely unaffected: it
		// still resolves through `effectiveParams` exactly as before.
		var liveParamText: [String: String] = [:]
		for control in template.debugControls {
			guard let defaultParam = effectiveParams[control.paramName] else {
				preconditionFailure("'\(template.name)': debug control on '$\(control.paramName)' has no default -- the parser should have required one")
			}
			let defaultValue: ComponentType
			switch defaultParam {
				case .float(let f): defaultValue = f
				case .int(let i): defaultValue = ComponentType(i)
			}
			liveParamText[control.paramName] = context.registerDebugControl(
				templateName: template.name, paramName: control.paramName, kind: control.kind, defaultValue: defaultValue)
		}

		// A `fn grid(spacing)` child is called through its grid cache. Done
		// after the debug controls above, since the spacing may read one.
		for decl in template.params {
			guard let grid = decl.grid, case .sampledFunction(let fnName) = env[decl.name] else { continue }
			let spacing = DSLInterpreter(context: context, params: effectiveParams, env: [:], liveParamText: liveParamText).evaluate(grid)
			env[decl.name] = .sampledFunction(context.registerGridCache(functionName: fnName, spacingExpression: spacing))
		}
		// Likewise a `fn taps(maxOffset)` child through its tap cache, when
		// tap caching is on.
		for decl in template.params {
			guard let taps = decl.taps, let tapScope = tapScopes[decl.name], case .sampledFunction(let fnName) = env[decl.name] else { continue }
			let maxOffset = DSLInterpreter(context: context, params: effectiveParams, env: [:], liveParamText: liveParamText).evaluate(taps)
			env[decl.name] = .sampledFunction(context.registerTapCache(functionName: fnName, maxOffsetExpression: maxOffset, scope: tapScope))
		}

		// What a `percell` block's per-cell function may recompute: the
		// children and the top-level lets, recorded as they're declared.
		var valueChildren: [String: any Node] = [:]
		for (decl, child) in zip(template.params, children) where !decl.isFunction {
			valueChildren[decl.name] = child
		}
		let nodeScope = DSLNodeScope(env: env, valueChildren: valueChildren)
		let interpreter = DSLInterpreter(context: context, params: effectiveParams, env: env, liveParamText: liveParamText, nodeScope: nodeScope)
		for stmt in template.body {
			let before = interpreter.environment
			interpreter.execute(stmt)
			nodeScope.record(stmt, envBefore: before, envAfter: interpreter.environment)
		}
		return interpreter.evaluate(template.returnExpr)
	}
}

/// A prefix unique to `qualifiedName`, applied to every function a module
/// defines so its MSL names can never collide with anything else's --
/// derived from the module's fully-qualified registration name (not
/// whatever bare text a `requires()` clause wrote) so two different
/// modules that both happen to be named "helpers" in two different
/// packages still get distinct prefixes. Non-identifier characters
/// (`.`/`-` are both legal in a quoted module name but not in MSL) become
/// underscores; a leading digit gets an "m_" guard since MSL identifiers
/// can't start with one.
func mslModulePrefix(for qualifiedName: String) -> String {
	var sanitized = String(qualifiedName.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
	if let first = sanitized.first, first.isNumber {
		sanitized = "m_" + sanitized
	}
	return sanitized + "__"
}

/// Turns a parsed module's functions into standalone, name-mangled MSL
/// function text. Each function gets its own fresh `MSLCodegenContext` (so
/// its local `tN` numbering is independent of whatever tree is calling
/// into it -- exactly how `MSLCodegenContext.emitFunction` already
/// isolates a node subtree) but shares one `siblingBindings` map so one
/// function in a module can call another by its plain name and still
/// resolve to the mangled definition.
func emitModuleFunctionsMSL(_ resolved: DSLResolvedModule, prefix: String) -> String {
	let siblingBindings: [String: DSLBinding] = Dictionary(
		uniqueKeysWithValues: resolved.module.funcs.map { ($0.name, .function(prefix + $0.name)) }
	)
	return resolved.module.funcs
		.map { emitFunctionMSL($0, prefix: prefix, siblingBindings: siblingBindings) }
		.joined(separator: "\n\n")
}

private func emitFunctionMSL(_ decl: DSLFuncDecl, prefix: String, siblingBindings: [String: DSLBinding]) -> String {
	let context = MSLCodegenContext()
	var env = siblingBindings
	for param in decl.params {
		// A function's own parameter shadows a sibling of the same name,
		// same as a node's `let` shadowing an outer binding.
		env[param.name] = .literal(param.name)
	}
	let interpreter = DSLInterpreter(context: context, params: [:], env: env)
	for stmt in decl.body {
		interpreter.execute(stmt)
	}
	let returnText = interpreter.evaluate(decl.returnExpr)
	let paramList = decl.params.map { "\($0.type) \($0.name)" }.joined(separator: ", ")
	return """
	inline \(decl.returnType) \(prefix)\(decl.name)(\(paramList)) {
		\(context.body())
		return \(returnText);
	}
	"""
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
	/// A module function (this node's own `requires()`, or a sibling
	/// function within the same module) -- calling it substitutes the
	/// name-mangled function name as the callee. Never needs `debugValues`
	/// threaded to it: a module `func` has no `param`/`$name` grammar at
	/// all (see `DSLParser.parseFuncDecl`), so it structurally can never
	/// reference a debug-controlled param.
	case function(String)
	/// A child sampled via `MSLCodegenContext.emitFunction` -- referencing
	/// it bare would be meaningless in MSL (there's no such thing as a
	/// function value), but calling it (`source(coord + ...)`) substitutes
	/// the generated function's name as the callee. Unlike `.function`
	/// above, the emitted function *does* take a `debugValues` parameter
	/// (the sampled child can itself have debug-annotated params), so a
	/// call through this binding must forward it -- see
	/// `DSLInterpreter.evaluate`'s `.call` case.
	case sampledFunction(String)

	var text: String {
		switch self {
			case .value(let v): return v.variableName
			case .literal(let s): return s
			case .function(let s): return s
			case .sampledFunction(let s): return s
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
	/// `$param` names that resolve to a live `debugValues[N]` slot instead
	/// of a baked literal -- checked before `params` in the `.param` case
	/// below. Empty for every call site except a node's own top-level
	/// `_emitMSL` (module functions and reduce-loop iterations never
	/// register debug controls of their own, but do inherit this dictionary
	/// unchanged when they share the same `DSLInterpreter`/sub-interpreter).
	private let liveParamText: [String: String]
	/// The node whose body this is, for `percell` blocks; nil in module
	/// functions and in a `percell` block's own per-cell function, where a
	/// `percell` is just computed in place.
	private let nodeScope: DSLNodeScope?

	init(context: MSLCodegenContext, params: [String: DSLParamValue], env: [String: DSLBinding], liveParamText: [String: String] = [:],
		 nodeScope: DSLNodeScope? = nil) {
		self.context = context
		self.params = params
		self.env = env
		self.liveParamText = liveParamText
		self.nodeScope = nodeScope
	}

	/// The current bindings, for `DSLNodeScope.record`.
	var environment: [String: DSLBinding] { env }

	func execute(_ stmt: DSLStmt) {
		switch stmt {
			case .constant(let decl), .variable(let decl):
				let type = decl.type ?? "float3"
				let text: String
				if case .reduce(let variable, let lo, let hi, let body, let result) = decl.value {
					text = evaluateReduce(variable: variable, lo: lo, hi: hi, body: body, result: result, type: type)
				} else if case .percell(let at, let spacing, let body, let result) = decl.value {
					text = evaluatePercell(at: at, spacing: spacing, body: body, result: result, type: type)
				} else {
					text = evaluate(decl.value)
				}
				env[decl.name] = .value(context.declare(text, type: type))

			case .assign(let name, let value):
				// The parser only lets a `var` in scope be assigned, so the
				// binding is always a declared local.
				guard let binding = env[name] else {
					preconditionFailure("DSL: assignment to unbound '\(name)'")
				}
				context.emitStatement("\(binding.text) = \(evaluate(value));")

			case .loop(let loop):
				executeLoop(loop)

			case .breakIf(let cond):
				context.emitStatement("if (\(evaluate(cond))) break;")
		}
	}

	/// Emits `loop(i in lo..<hi, max: n) { body }` as a real MSL `for` loop.
	/// The hard bound `lo + n` is a literal in the loop condition, so the
	/// GPU never runs more than n iterations whatever `hi` evaluates to
	/// (huge, negative, NaN); `hi` itself is evaluated once, before the
	/// loop, and ends it early. Body statements are interpreted in a child
	/// interpreter so their `let`s stay scoped to the loop body, the same
	/// way MSL scopes them; `var`s declared outside keep their binding, so
	/// assignments to them carry from one iteration to the next.
	private func executeLoop(_ loop: DSLLoop) {
		let loValue = resolveInt(loop.lo)
		let maxValue = resolveInt(loop.max)
		precondition(maxValue >= 0, "DSL: loop max must not be negative, got \(maxValue)")

		let end = context.declare("float(\(evaluate(loop.hi)))", type: "float")
		let counter = context.freshVariableName()
		context.emitStatement("for (int \(counter) = \(loValue); \(counter) < \(loValue + maxValue); \(counter)++) {")
		context.emitStatement("if (!(float(\(counter)) < \(end.variableName))) break;")

		var bodyEnv = env
		bodyEnv[loop.variable] = .literal(counter)
		let body = DSLInterpreter(context: context, params: params, env: bodyEnv, liveParamText: liveParamText, nodeScope: nodeScope)
		for stmt in loop.body {
			body.execute(stmt)
		}
		context.emitStatement("}")
	}

	func evaluate(_ expr: DSLExpr) -> String {
		switch expr {
			case .number(let text):
				return text

			case .identifier(let name):
				// A bound name (child/let/param/reduce variable) substitutes
				// its resolved text. An *unbound* one is assumed to be a
				// passthrough MSL constant (`M_PI_F`) or type name, exactly
				// the same permissive rule already applied to unbound names
				// in call position (see the `.call` case below) -- there's
				// no meaningful way to distinguish "a real typo" from "a
				// legitimate bare MSL identifier this DSL doesn't know
				// about" at this layer, and a genuine typo still fails
				// loudly at the Metal compile step, just later.
				return env[name]?.text ?? name

			case .param(let name):
				if let liveText = liveParamText[name] {
					return liveText
				}
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
					if case .sampledFunction(let fnName) = env[name] {
						// The emitted function also takes `debugValues` (it
						// may itself contain debug-annotated params) and the
						// grid-cache textures -- see
						// `MSLCodegenContext.emitFunction`.
						return "\(fnName)(\(argsText), debugValues EVOLV_CACHE_ARGS)"
					}
					if let binding = env[name] {
						return "\(binding.text)(\(argsText))"
					}
					return "\(name)(\(argsText))"
				}
				return "\(evaluate(callee))(\(argsText))"

			case .reduce(let variable, let lo, let hi, let body, let result):
				// Nothing here says what type the terms are, so this can't
				// declare an accumulator: unroll.
				return evaluateReduce(variable: variable, lo: lo, hi: hi, body: body, result: result, type: nil)

			case .percell(let at, let spacing, let body, let result):
				return evaluatePercell(at: at, spacing: spacing, body: body, result: result, type: "float3")
		}
	}

	/// False computes every `percell` block in place, as if it weren't
	/// marked -- for tests comparing the two.
	nonisolated(unsafe) static var cachesPercellBlocks = true

	/// `percell(at, spacing) { body; result }` as the value of a `type`
	/// local. Computed in place, it's just the block: `body` in its own
	/// scope, then `result` (an `average` result accumulating as `type`,
	/// exactly as if the `let` had been initialized with it directly).
	///
	/// With sample caching on, inside a node, and when everything the block
	/// reads besides `at` is the same at every coordinate (see
	/// `DSLNodeScope.cellInputs`), the block is also emitted as a function
	/// of the cell centre: its own copies of the top-level lets and value
	/// children it needs, then the block with `at` bound to the function's
	/// `coord`. The renderer runs that once per cell into a texture
	/// (`MSLCodegenContext.registerPercellCache`), and here the block is
	/// only computed when the read misses. Both run the same statements on
	/// the same values, so a texel holds what the block would have computed.
	/// Only float3 and float blocks are cached.
	private func evaluatePercell(at: String, spacing: DSLExpr, body: [DSLStmt], result: DSLExpr, type: String) -> String {
		let isScalar = type == "float"
		guard Self.cachesPercellBlocks, context.sampleCachingEnabled, isScalar || type == "float3", let nodeScope,
			  let inputs = nodeScope.cellInputs(at: at, body: body, result: result, env: env) else {
			return evaluateBlock(body: body, result: result, type: type)
		}

		let cellFunction = context.emitFunction { cellContext in
			var cellEnv = nodeScope.env.filter { if case .value = $0.value { return false } else { return true } }
			for (name, child) in inputs.valueChildren {
				cellEnv[name] = .value(child.codegenMSL(into: cellContext))
			}
			let cell = DSLInterpreter(context: cellContext, params: params, env: cellEnv, liveParamText: liveParamText)
			for decl in inputs.lets {
				cell.execute(.constant(decl))
			}
			cell.env[at] = .literal("coord")
			let value = cell.evaluateBlock(body: body, result: result, type: type)
			return isScalar ? "float3(\(value))" : value
		}
		let spacingText = DSLInterpreter(context: context, params: params, env: [:], liveParamText: liveParamText).evaluate(spacing)
		let read = context.registerPercellCache(functionName: cellFunction, spacingExpression: spacingText)

		let value = context.freshVariableName()
		context.emitStatement("float3 \(value);")
		context.emitStatement("if (!\(read)(\(evaluate(.identifier(at))), \(value), debugValues EVOLV_CACHE_ARGS)) {")
		let computed = evaluateBlock(body: body, result: result, type: type)
		context.emitStatement("\(value) = \(isScalar ? "float3(\(computed))" : computed);")
		context.emitStatement("}")
		return isScalar ? "\(value).x" : value
	}

	/// A `percell` block computed in place.
	private func evaluateBlock(body: [DSLStmt], result: DSLExpr, type: String) -> String {
		let block = DSLInterpreter(context: context, params: params, env: env, liveParamText: liveParamText, nodeScope: nodeScope)
		for stmt in body {
			block.execute(stmt)
		}
		if case .reduce(let variable, let lo, let hi, let reduceBody, let reduceResult) = result {
			return block.evaluateReduce(variable: variable, lo: lo, hi: hi, body: reduceBody, result: reduceResult, type: type)
		}
		if case .percell(let innerAt, let innerSpacing, let innerBody, let innerResult) = result {
			return block.evaluatePercell(at: innerAt, spacing: innerSpacing, body: innerBody, result: innerResult, type: type)
		}
		return block.evaluate(result)
	}

	/// False makes every `average` unroll, as all of them did before they
	/// could become loops -- for tests comparing the two.
	nonisolated(unsafe) static var emitsReductionLoops = true

	/// `average(variable in lo...hi) { body; result }`: the mean of `result`
	/// over the range, summed left to right and then divided by the count.
	///
	/// With a known `type` (the `let` it initializes, or the enclosing
	/// `average` whose result it is) it becomes a runtime MSL `for` loop
	/// adding each iteration's result into an accumulator of that type, so
	/// blur's 21x21 taps are one loop body instead of 441 copies. The
	/// accumulator starts at 0 and 0 + t == t, so the sum is the same as
	/// the unrolled `t0 + t1 + ...`; scalar terms into a vector accumulator
	/// broadcast, which is what declaring the unrolled sum as that type did.
	/// Without a type it unrolls `body`/`result` once per iteration instead,
	/// each copy independently scoped.
	private func evaluateReduce(variable: String, lo: DSLExpr, hi: DSLExpr, body: [DSLStmt], result: DSLExpr, type: String?) -> String {
		let loValue = resolveInt(lo)
		let hiValue = resolveInt(hi)
		precondition(loValue <= hiValue, "DSL: empty reduce range \(loValue)...\(hiValue)")
		let count = mslFloatLiteral(ComponentType(hiValue - loValue + 1))

		if let type, Self.emitsReductionLoops {
			let sum = context.declare("0.0", type: type)
			let counter = context.freshVariableName()
			context.emitStatement("for (int \(counter) = \(loValue); \(counter) <= \(hiValue); \(counter)++) {")
			var bodyEnv = env
			bodyEnv[variable] = .literal(counter)
			let iteration = DSLInterpreter(context: context, params: params, env: bodyEnv, liveParamText: liveParamText, nodeScope: nodeScope)
			for stmt in body {
				iteration.execute(stmt)
			}
			let term: String
			if case .reduce(let innerVariable, let innerLo, let innerHi, let innerBody, let innerResult) = result {
				term = iteration.evaluateReduce(variable: innerVariable, lo: innerLo, hi: innerHi, body: innerBody, result: innerResult, type: type)
			} else {
				term = iteration.evaluate(result)
			}
			context.emitStatement("\(sum.variableName) = \(sum.variableName) + \(term);")
			context.emitStatement("}")
			return "(\(sum.variableName) / \(count))"
		}

		var terms: [String] = []
		for i in loValue...hiValue {
			var iterEnv = env
			iterEnv[variable] = .literal(String(i))
			let iteration = DSLInterpreter(context: context, params: params, env: iterEnv, liveParamText: liveParamText, nodeScope: nodeScope)
			for stmt in body {
				iteration.execute(stmt)
			}
			terms.append(iteration.evaluate(result))
		}
		return "((\(terms.joined(separator: " + "))) / \(count))"
	}

	private func resolveInt(_ expr: DSLExpr) -> Int {
		switch expr {
			case .number(let text):
				guard let i = Int(text) else {
					preconditionFailure("DSL: expected an integer literal in an average/loop bound, got '\(text)'")
				}
				return i
			case .param(let name):
				guard case .int(let i)? = params[name] else {
					preconditionFailure("DSL: expected an int param '$\(name)' in an average/loop bound")
				}
				return i
			default:
				preconditionFailure("DSL: average bounds and loop lo/max must be integer literals or int params")
		}
	}
}

/// What a node's `percell` blocks may recompute in their per-cell function
/// (see `DSLInterpreter.evaluatePercell`): the node's children and its
/// top-level lets, as long as none of it depends on `coord`, since the
/// per-cell function recomputes them at the cell centre rather than at the
/// point the node was asked for.
final class DSLNodeScope {
	/// The bindings the node's body starts with: `coord`, modules, children.
	let env: [String: DSLBinding]
	private let valueChildren: [String: any Node]

	private struct TopLevelLet {
		let decl: DSLLetStmt
		/// Its MSL local, which is how a reference to it is recognised.
		let variableName: String
		/// Whether its value is the same at every coordinate, so a cell
		/// function may recompute it.
		let uniform: Bool
		/// Earlier top-level lets (indices) and value children it reads.
		let lets: Set<Int>
		let children: Set<String>
	}
	private var lets: [TopLevelLet] = []
	private var independentChildren: [String: Bool] = [:]

	init(env: [String: DSLBinding], valueChildren: [String: any Node]) {
		self.env = env
		self.valueChildren = valueChildren
	}

	/// Called after each top-level statement of the node's body runs. Only
	/// a `let` is recorded: a block reading any other local (a `var`, a
	/// loop's) isn't cached.
	func record(_ stmt: DSLStmt, envBefore: [String: DSLBinding], envAfter: [String: DSLBinding]) {
		guard case .constant(let decl) = stmt, case .value(let value)? = envAfter[decl.name] else { return }
		let free = dslFreeNames(body: [], result: decl.value)
		let resolved = resolve(free.read, env: envBefore)
		lets.append(TopLevelLet(decl: decl, variableName: value.variableName,
								uniform: resolved != nil && free.assigned.isEmpty && !dslContainsPercell(decl.value),
								lets: resolved?.lets ?? [], children: resolved?.children ?? []))
	}

	/// What a cell function needs to compute `percell(at, ...) { body;
	/// result }` from the cell centre alone -- the top-level lets in
	/// declaration order and the value children -- or nil if the block
	/// reads anything that could differ between coordinates besides `at`
	/// (`coord`, a coordinate-dependent child or let, a local of an
	/// enclosing block) or assigns to anything outside itself.
	func cellInputs(at: String, body: [DSLStmt], result: DSLExpr, env: [String: DSLBinding]) -> (lets: [DSLLetStmt], valueChildren: [(String, any Node)])? {
		let free = dslFreeNames(body: body, result: result)
		guard free.assigned.isEmpty, let direct = resolve(free.read.subtracting([at]), env: env) else { return nil }
		var needed = Set<Int>()
		var children = direct.children
		var pending = Array(direct.lets)
		while let index = pending.popLast() {
			guard needed.insert(index).inserted else { continue }
			guard lets[index].uniform else { return nil }
			pending.append(contentsOf: lets[index].lets)
			children.formUnion(lets[index].children)
		}
		for name in children where !isIndependent(name) {
			return nil
		}
		return (needed.sorted().map { lets[$0].decl }, children.sorted().map { ($0, valueChildren[$0]!) })
	}

	/// Sorts names read under `env` into top-level lets and value children;
	/// nil if one is `coord` or a local that isn't a top-level let.
	/// Modules, function children and unbound names (MSL builtins) are
	/// the same everywhere.
	private func resolve(_ names: Set<String>, env: [String: DSLBinding]) -> (lets: Set<Int>, children: Set<String>)? {
		var foundLets = Set<Int>()
		var children = Set<String>()
		for name in names {
			if name == "coord" { return nil }
			guard let binding = env[name] else { continue }
			if let topLevel = self.env[name], topLevel.text == binding.text {
				if case .value = binding { children.insert(name) }
				continue
			}
			guard case .value(let value) = binding,
				  let index = lets.lastIndex(where: { $0.variableName == value.variableName }) else {
				return nil
			}
			foundLets.insert(index)
		}
		return (foundLets, children)
	}

	private func isIndependent(_ child: String) -> Bool {
		if let known = independentChildren[child] { return known }
		let independent = dslIsCoordinateIndependent(valueChildren[child]!)
		independentChildren[child] = independent
		return independent
	}
}

/// Whether `node`'s value is the same at every coordinate: constants, and
/// DSL nodes whose definition never mentions `coord` and whose value
/// children are themselves independent. (A function child is only ever
/// called at points the node computes, which can't depend on the
/// coordinate without mentioning `coord`.) Anything else counts as
/// dependent.
func dslIsCoordinateIndependent(_ node: any Node) -> Bool {
	if node is Constant || node is ConstantTriplet { return true }
	guard let dsl = node as? DSLCodegenNode else { return false }
	let free = dslFreeNames(body: dsl.template.body, result: dsl.template.returnExpr)
	guard !free.read.contains("coord") else { return false }
	for (decl, child) in zip(dsl.template.params, dsl.children) where !decl.isFunction {
		guard dslIsCoordinateIndependent(child) else { return false }
	}
	return true
}

/// The names `body` then `result` read, and assign, without binding them
/// first. Called names count as read (an unbound one is an MSL builtin).
func dslFreeNames(body: [DSLStmt], result: DSLExpr?) -> (read: Set<String>, assigned: Set<String>) {
	var read = Set<String>()
	var assigned = Set<String>()
	func expr(_ e: DSLExpr, _ bound: Set<String>) {
		switch e {
			case .number, .param:
				break
			case .identifier(let name):
				if !bound.contains(name) { read.insert(name) }
			case .unary(_, let operand):
				expr(operand, bound)
			case .binary(_, let lhs, let rhs):
				expr(lhs, bound)
				expr(rhs, bound)
			case .ternary(let cond, let then, let else_):
				expr(cond, bound)
				expr(then, bound)
				expr(else_, bound)
			case .call(let callee, let args):
				expr(callee, bound)
				args.forEach { expr($0, bound) }
			case .member(let base, _):
				expr(base, bound)
			case .reduce(let variable, let lo, let hi, let body, let result):
				expr(lo, bound)
				expr(hi, bound)
				block(body, result, bound.union([variable]))
			case .percell(let at, let spacing, let body, let result):
				expr(.identifier(at), bound)
				expr(spacing, bound)
				block(body, result, bound)
		}
	}
	func block(_ stmts: [DSLStmt], _ result: DSLExpr?, _ outer: Set<String>) {
		var bound = outer
		for stmt in stmts {
			switch stmt {
				case .constant(let decl), .variable(let decl):
					expr(decl.value, bound)
					bound.insert(decl.name)
				case .assign(let name, let value):
					expr(value, bound)
					if !bound.contains(name) { assigned.insert(name) }
				case .loop(let loop):
					expr(loop.lo, bound)
					expr(loop.hi, bound)
					expr(loop.max, bound)
					block(loop.body, nil, bound.union([loop.variable]))
				case .breakIf(let cond):
					expr(cond, bound)
			}
		}
		if let result { expr(result, bound) }
	}
	block(body, result, [])
	return (read, assigned)
}

/// Whether `e` contains a `percell` block.
private func dslContainsPercell(_ e: DSLExpr) -> Bool {
	switch e {
		case .percell: return true
		case .number, .param, .identifier: return false
		case .unary(_, let operand): return dslContainsPercell(operand)
		case .binary(_, let lhs, let rhs): return dslContainsPercell(lhs) || dslContainsPercell(rhs)
		case .ternary(let c, let t, let f): return [c, t, f].contains(where: dslContainsPercell)
		case .call(let callee, let args): return dslContainsPercell(callee) || args.contains(where: dslContainsPercell)
		case .member(let base, _): return dslContainsPercell(base)
		case .reduce(_, let lo, let hi, let body, let result):
			return dslContainsPercell(lo) || dslContainsPercell(hi) || dslContainsPercell(result) || body.contains {
				switch $0 {
					case .constant(let d), .variable(let d): return dslContainsPercell(d.value)
					case .assign(_, let v), .breakIf(let v): return dslContainsPercell(v)
					case .loop: return true
				}
			}
	}
}

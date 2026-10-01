//
//  DSLParser.swift
//  Evolv.io
//
//  Spike: recursive-descent parser producing a DSLTemplate from source text
//  like:
//
//    node "mod"(v0, v1) {
//        let isZeroMask: bool3 = v1 == float3(0.0)
//        let safeDivisor = select(v1, float3(1.0), isZeroMask)
//        let remainder = fmod(v0, safeDivisor)
//        let isNegativeRemainder: bool3 = remainder < float3(0.0)
//        return select(remainder, remainder + v1, isNegativeRemainder)
//    }
//
//  See DSLLexer.swift for the tokenizer and why this is hand-rolled, and
//  DSLCodegenNode.swift for how the resulting DSLTemplate is turned into
//  MSL. Grammar (informal, lowest to highest precedence):
//
//    file       := nodeDecl | moduleDecl | packageDecl   -- one per file
//    nodeDecl   := 'node' STRING '(' paramDecl (',' paramDecl)* ')'
//                  ('->' ('scalar'|'vector'))?   -- output type, for the generator
//                  'nonconst'?   -- a no-param node the generator treats
//                                      as a function, not a variable
//                  ('requires' '(' requirement (',' requirement)* ')')?
//    requirement := ('::')? (IDENT|STRING)  -- '::' = look only in library
//                  roots scanned before this file's own (see DSLLibrary.scan)
//                  '{' (stmt | paramStmt)* 'return' expr '}'
//    paramDecl  := IDENT (':' (IDENT | ('grid' | 'taps') '(' expr ')')+)?
//                  -- ": fn" marks a sampled child;
//                  ": scalar"/": vector" (optionally after "fn") is the
//                  generator's preferred argument type; "grid(spacing)"
//                  (fn only) says the child is only sampled at grid-cell
//                  centres, so it can be rendered into a texture once;
//                  "taps(maxOffset)" (fn only) says it's only sampled
//                  within maxOffset of coord, so with tap caching on it
//                  can be interpolated from a texture
//    paramStmt  := 'param' '$' IDENT ':' IDENT '=' signedNumber debugClause?
//                  -- a self-contained default for a `$name` reference,
//                  used when nothing external supplies one
//    debugClause := 'debug' ('toggle' | 'slider' '(' signedNumber ',' signedNumber ')')
//    signedNumber := '-'? NUMBER          -- a literal sign, not the unary
//                  '-' expression rule below (the lexer never folds a sign
//                  into NUMBER itself, so this is handled explicitly)
//                  -- only valid on a 'float' param; registers it as a live,
//                  no-recompile-needed uniform NodeDebuggingView can surface
//                  as a Toggle/Slider (see MSLCodegenContext.registerDebugControl)
//    moduleDecl := 'module' STRING '{' funcDecl* '}'
//    funcDecl   := 'func' IDENT '(' (IDENT ':' IDENT (',' IDENT ':' IDENT)*)? ')'
//                  '->' IDENT '{' stmt* 'return' expr '}'
//    packageDecl := 'package' STRING          -- a whole file's content
//    stmt       := letStmt | varStmt | assignStmt | loopStmt | breakStmt
//    letStmt    := 'let' IDENT (':' IDENT)? '=' expr
//    varStmt    := 'var' IDENT (':' IDENT)? '=' expr
//    assignStmt := IDENT '=' expr             -- IDENT must be a `var` in scope
//    loopStmt   := 'loop' '(' IDENT 'in' additive '..<' additive ','
//                  'max' ':' additive ')' '{' stmt* '}'
//                  -- a real runtime `for` loop; lo and max must be int
//                  literals or int `$param`s, hi can be any runtime scalar
//    breakStmt  := 'break' 'if' expr          -- only inside a loopStmt
//    expr       := ternary
//    ternary    := or ('?' expr ':' expr)?
//    or         := and ('||' and)*
//    and        := bitAnd ('&&' bitAnd)*
//    bitAnd     := equality ('&' equality)*        -- e.g. `and`'s bit-twiddling
//    equality   := comparison (('=='|'!=') comparison)*
//    comparison := additive (('<'|'<='|'>'|'>=') additive)*
//    additive   := multiplicative (('+'|'-') multiplicative)*
//    multiplicative := unary (('*'|'/') unary)*
//    unary      := ('-'|'!')? postfix
//    postfix    := primary ('.' IDENT | '(' argList ')')*
//    primary    := NUMBER | IDENT genericSuffix? | '$' IDENT | '(' expr ')' | reduceExpr
//                  | percellExpr
//    genericSuffix := '<' IDENT '>'                 -- folds into one identifier,
//                  e.g. `as_type<uint3>`, so it can be called like any other
//                  passthrough MSL builtin (see DSLInterpreter's unbound-call
//                  handling) without the grammar needing real generics
//    reduceExpr := 'average' '(' IDENT 'in' expr '...' expr ')'
//                  '{' stmt* expr '}'     -- no breakStmt, even inside a loop
//    percellExpr := 'percell' '(' IDENT ',' expr ')' '{' stmt* expr '}'
//                  -- a block that depends only on which grid cell IDENT
//                  is; the spacing follows grid(...)'s rules
//
//  Bare (non-call) identifiers that aren't bound to a child/let/param are
//  passed through as literal text too (not just in call position) -- see
//  DSLInterpreter.evaluate's `.identifier` case -- so a node can reference
//  a plain MSL constant like `M_PI_F` without it needing a binding.
//

struct DSLParseError: Error, CustomStringConvertible {
	let message: String
	var description: String { message }
}

final class DSLParser {
	private let tokens: [DSLToken]
	private var pos = 0
	/// Names declared in each enclosing block, innermost last, mapped to
	/// whether they're a `var` -- so `x = ...` can be rejected unless `x`
	/// is a `var` in scope (a `let` or a child param of the same name
	/// shadows it).
	private var scopes: [[String: Bool]] = []
	/// How many `loop`s enclose the current statement; `break if` needs at
	/// least one. Reset to 0 inside an `average` block (see parseReduce).
	private var loopDepth = 0

	init(_ source: String) throws {
		tokens = try DSLLexer(source).tokenize()
	}

	/// Dispatches on a file's leading keyword -- the entry point
	/// `DSLLibrary.scan` uses (`parseTemplate()` below is kept as a direct
	/// entry point too, for call sites that only ever expect a node, like
	/// `DSLSampleDefinitions`).
	func parseFile() throws -> DSLFile {
		guard case .identifier(let keyword) = peek() else {
			throw DSLParseError(message: "Expected 'node', 'module', or 'package', found \(peek())")
		}
		switch keyword {
			case "node": return .node(try parseTemplate())
			case "module": return .module(try parseModule())
			case "package": return .package(name: try parsePackageManifest())
			default: throw DSLParseError(message: "Expected 'node', 'module', or 'package', found '\(keyword)'")
		}
	}

	func parseTemplate() throws -> DSLTemplate {
		try expectIdentifier("node")
		let name = try expectString()
		try expect(.lparen)
		var params: [DSLParam] = []
		if !check(.rparen) {
			repeat {
				params.append(try parseParamDecl())
			} while match(.comma)
		}
		try expect(.rparen)

		// '->' is .minus then .gt, as in parseFuncDecl.
		var outputType: NodeValueType? = nil
		if match(.minus) {
			try expect(.gt)
			let typeName = try expectAnyIdentifier()
			guard let type = NodeValueType(rawValue: typeName) else {
				throw DSLParseError(message: "Unknown output type '\(typeName)' for node '\(name)' -- expected 'scalar' or 'vector'")
			}
			outputType = type
		}

		let isNonconst = checkIdentifier("nonconst")
		if isNonconst {
			guard params.isEmpty else {
				throw DSLParseError(message: "'nonconst' on node '\(name)', which has params -- only a node with no params can be a terminal, so only it needs 'nonconst'")
			}
			pos += 1
		}

		var requires: [String] = []
		if checkIdentifier("requires") {
			pos += 1
			try expect(.lparen)
			if !check(.rparen) {
				repeat {
					requires.append(try expectIdentifierOrString())
				} while match(.comma)
			}
			try expect(.rparen)
		}

		try expect(.lbrace)
		scopes = [Dictionary(params.map { ($0.name, false) }, uniquingKeysWith: { a, _ in a })]
		var body: [DSLStmt] = []
		var paramDefaults: [String: DSLParamValue] = [:]
		var debugControls: [DSLDebugControl] = []
		while true {
			if checkIdentifier("param") {
				let (paramName, value, debugControl) = try parseParamDefaultStmt()
				paramDefaults[paramName] = value
				if let debugControl { debugControls.append(debugControl) }
			} else if let stmt = try parseStmt() {
				body.append(stmt)
			} else {
				break
			}
		}
		try expectIdentifier("return")
		let returnExpr = try parseExpr()
		try expect(.rbrace)
		try expect(.eof)

		return DSLTemplate(name: name, params: params, outputType: outputType, isNonconst: isNonconst, requires: requires, paramDefaults: paramDefaults, debugControls: debugControls, body: body, returnExpr: returnExpr)
	}

	private func parseModule() throws -> DSLModule {
		try expectIdentifier("module")
		let name = try expectString()
		try expect(.lbrace)
		var funcs: [DSLFuncDecl] = []
		while checkIdentifier("func") {
			funcs.append(try parseFuncDecl())
		}
		try expect(.rbrace)
		try expect(.eof)
		return DSLModule(name: name, funcs: funcs)
	}

	private func parseFuncDecl() throws -> DSLFuncDecl {
		try expectIdentifier("func")
		let name = try expectAnyIdentifier()
		try expect(.lparen)
		var params: [(name: String, type: String)] = []
		if !check(.rparen) {
			repeat {
				let paramName = try expectAnyIdentifier()
				try expect(.colon)
				let paramType = try expectAnyIdentifier()
				params.append((paramName, paramType))
			} while match(.comma)
		}
		try expect(.rparen)
		// '->' isn't its own token -- the lexer emits plain '-' then '>',
		// which is exactly .minus followed by .gt (see DSLLexer's
		// lexPunctuation: '-' never looks ahead for a following '>').
		try expect(.minus)
		try expect(.gt)
		let returnType = try expectAnyIdentifier()

		try expect(.lbrace)
		scopes = [Dictionary(params.map { ($0.name, false) }, uniquingKeysWith: { a, _ in a })]
		var body: [DSLStmt] = []
		while let stmt = try parseStmt() {
			body.append(stmt)
		}
		try expectIdentifier("return")
		let returnExpr = try parseExpr()
		try expect(.rbrace)

		return DSLFuncDecl(name: name, params: params, returnType: returnType, body: body, returnExpr: returnExpr)
	}

	private func parsePackageManifest() throws -> String {
		try expectIdentifier("package")
		let name = try expectString()
		try expect(.eof)
		return name
	}

	private func parseParamDefaultStmt() throws -> (name: String, value: DSLParamValue, debugControl: DSLDebugControl?) {
		try expectIdentifier("param")
		guard case .param(let name) = peek() else {
			throw DSLParseError(message: "Expected '$name' after 'param', found \(peek())")
		}
		pos += 1
		try expect(.colon)
		let type = try expectAnyIdentifier()
		try expect(.assign)
		let literal = try expectNumberLiteral(context: "default for param '$\(name)'")

		let value: DSLParamValue
		switch type {
			case "float":
				value = .float(ComponentType(literal))
			case "int":
				guard literal == literal.rounded() else {
					throw DSLParseError(message: "Invalid int literal '\(literal)' for param '$\(name)'")
				}
				value = .int(Int(literal))
			default:
				throw DSLParseError(message: "Unknown param type '\(type)' for '$\(name)' -- expected 'float' or 'int'")
		}

		var debugControl: DSLDebugControl? = nil
		if checkIdentifier("debug") {
			pos += 1
			guard case .float = value else {
				throw DSLParseError(message: "'debug' is only valid on a 'float' param, found on int param '$\(name)'")
			}
			if checkIdentifier("toggle") {
				pos += 1
				debugControl = DSLDebugControl(paramName: name, kind: .toggle)
			} else if checkIdentifier("slider") {
				pos += 1
				try expect(.lparen)
				let lo = try expectNumberLiteral(context: "slider min for param '$\(name)'")
				try expect(.comma)
				let hi = try expectNumberLiteral(context: "slider max for param '$\(name)'")
				try expect(.rparen)
				debugControl = DSLDebugControl(paramName: name, kind: .slider(min: ComponentType(lo), max: ComponentType(hi)))
			} else {
				throw DSLParseError(message: "Expected 'toggle' or 'slider(min, max)' after 'debug' for param '$\(name)', found \(peek())")
			}
		}

		return (name, value, debugControl)
	}

	private func parseParamDecl() throws -> DSLParam {
		let name = try expectAnyIdentifier()
		var isFunction = false
		var preferredType: NodeValueType? = nil
		var grid: DSLExpr? = nil
		var taps: DSLExpr? = nil
		if match(.colon) {
			// One or more words up to the next ',' or ')': at most one role
			// (fn/value), at most one type (scalar/vector) and at most one
			// grid(...), e.g. `fn scalar` or `fn grid(2.0 / $width)`.
			var sawRole = false
			repeat {
				let word = try expectAnyIdentifier()
				if word == "grid" {
					guard grid == nil else {
						throw DSLParseError(message: "Param '\(name)' has more than one grid")
					}
					try expect(.lparen)
					let spacing = try parseExpr()
					try expect(.rparen)
					try validateGridSpacing(spacing, param: name)
					grid = spacing
				} else if word == "taps" {
					guard taps == nil else {
						throw DSLParseError(message: "Param '\(name)' has more than one taps")
					}
					try expect(.lparen)
					let maxOffset = try parseExpr()
					try expect(.rparen)
					try validateGridSpacing(maxOffset, param: name)
					taps = maxOffset
				} else if word == "fn" || word == "value" {
					guard !sawRole else {
						throw DSLParseError(message: "Param '\(name)' has more than one role")
					}
					sawRole = true
					isFunction = word == "fn"
				} else if let type = NodeValueType(rawValue: word) {
					guard preferredType == nil else {
						throw DSLParseError(message: "Param '\(name)' has more than one type")
					}
					preferredType = type
				} else {
					throw DSLParseError(message: "Unknown param role or type '\(word)' for '\(name)' -- expected 'fn', 'value', 'scalar' or 'vector'")
				}
			} while !check(.comma) && !check(.rparen)
		}
		if grid != nil && !isFunction {
			throw DSLParseError(message: "Param '\(name)' has a grid but isn't 'fn' -- only a sampled child can have one")
		}
		if taps != nil && !isFunction {
			throw DSLParseError(message: "Param '\(name)' has taps but isn't 'fn' -- only a sampled child can have them")
		}
		if grid != nil && taps != nil {
			throw DSLParseError(message: "Param '\(name)' has both a grid and taps")
		}
		return DSLParam(name: name, isFunction: isFunction, preferredType: preferredType, grid: grid, taps: taps)
	}

	/// A grid spacing is evaluated once per render (to size the texture),
	/// where there is no coordinate and no child value -- so it may only
	/// use numbers, `$param`s, operators and calls to MSL builtins.
	private func validateGridSpacing(_ expr: DSLExpr, param: String) throws {
		switch expr {
			case .number, .param:
				return
			case .unary(_, let operand):
				try validateGridSpacing(operand, param: param)
			case .binary(_, let lhs, let rhs):
				try validateGridSpacing(lhs, param: param)
				try validateGridSpacing(rhs, param: param)
			case .ternary(let cond, let then, let else_):
				for e in [cond, then, else_] { try validateGridSpacing(e, param: param) }
			case .call(.identifier, let args):
				for e in args { try validateGridSpacing(e, param: param) }
			default:
				throw DSLParseError(message: "The grid spacing for '\(param)' may only use numbers, $params, operators and builtin calls")
		}
	}

	/// One statement, or nil (consuming nothing) if the next token doesn't
	/// start one -- the caller then expects `return` or a trailing
	/// expression.
	private func parseStmt() throws -> DSLStmt? {
		if checkIdentifier("let") {
			return .constant(try parseLetStmt(keyword: "let"))
		}
		if checkIdentifier("var") {
			return .variable(try parseLetStmt(keyword: "var"))
		}
		if checkIdentifier("loop") {
			return .loop(try parseLoop())
		}
		if checkIdentifier("break") {
			pos += 1
			guard loopDepth > 0 else {
				throw DSLParseError(message: "'break if' is only valid inside a 'loop' (and not inside an 'average' block)")
			}
			try expectIdentifier("if")
			return .breakIf(try parseExpr())
		}
		if case .identifier(let name) = peek(), pos + 1 < tokens.count, tokens[pos + 1] == .assign {
			guard lookupIsMutable(name) == true else {
				throw DSLParseError(message: "Can't assign to '\(name)': only a 'var' can be reassigned")
			}
			pos += 2
			return .assign(name: name, value: try parseExpr())
		}
		return nil
	}

	private func parseLetStmt(keyword: String) throws -> DSLLetStmt {
		try expectIdentifier(keyword)
		let name = try expectAnyIdentifier()
		var type: String? = nil
		if match(.colon) {
			type = try expectAnyIdentifier()
		}
		try expect(.assign)
		let value = try parseExpr()
		declare(name, mutable: keyword == "var")
		return DSLLetStmt(name: name, type: type, value: value)
	}

	private func parseLoop() throws -> DSLLoop {
		try expectIdentifier("loop")
		try expect(.lparen)
		let variable = try expectAnyIdentifier()
		try expectIdentifier("in")
		let lo = try parseAdditive()
		try expect(.halfOpenRange)
		let hi = try parseAdditive()
		try expect(.comma)
		try expectIdentifier("max")
		try expect(.colon)
		let max = try parseAdditive()
		try expect(.rparen)
		for (label, bound) in [("lower bound", lo), ("max", max)] {
			switch bound {
				case .number(let text) where Int(text) != nil: continue
				case .param: continue
				default: throw DSLParseError(message: "loop \(label) must be an integer literal or an int $param")
			}
		}
		try expect(.lbrace)
		scopes.append([variable: false])
		loopDepth += 1
		var body: [DSLStmt] = []
		while let stmt = try parseStmt() {
			body.append(stmt)
		}
		loopDepth -= 1
		scopes.removeLast()
		try expect(.rbrace)
		return DSLLoop(variable: variable, lo: lo, hi: hi, max: max, body: body)
	}

	private func declare(_ name: String, mutable: Bool) {
		if scopes.isEmpty { scopes.append([:]) }
		scopes[scopes.count - 1][name] = mutable
	}

	/// nil if `name` isn't declared in any enclosing block.
	private func lookupIsMutable(_ name: String) -> Bool? {
		for scope in scopes.reversed() {
			if let mutable = scope[name] { return mutable }
		}
		return nil
	}

	// MARK: - Expressions

	private func parseExpr() throws -> DSLExpr {
		try parseTernary()
	}

	private func parseTernary() throws -> DSLExpr {
		let cond = try parseOr()
		if match(.question) {
			let then = try parseExpr()
			try expect(.colon)
			let else_ = try parseExpr()
			return .ternary(cond: cond, then: then, else_: else_)
		}
		return cond
	}

	private func parseOr() throws -> DSLExpr {
		var lhs = try parseAnd()
		while match(.or) {
			lhs = .binary(op: "||", lhs: lhs, rhs: try parseAnd())
		}
		return lhs
	}

	private func parseAnd() throws -> DSLExpr {
		var lhs = try parseBitwiseAnd()
		while match(.and) {
			lhs = .binary(op: "&&", lhs: lhs, rhs: try parseBitwiseAnd())
		}
		return lhs
	}

	private func parseBitwiseAnd() throws -> DSLExpr {
		var lhs = try parseEquality()
		while match(.amp) {
			lhs = .binary(op: "&", lhs: lhs, rhs: try parseEquality())
		}
		return lhs
	}

	private func parseEquality() throws -> DSLExpr {
		var lhs = try parseComparison()
		while true {
			if match(.eq) { lhs = .binary(op: "==", lhs: lhs, rhs: try parseComparison()) }
			else if match(.neq) { lhs = .binary(op: "!=", lhs: lhs, rhs: try parseComparison()) }
			else { break }
		}
		return lhs
	}

	private func parseComparison() throws -> DSLExpr {
		var lhs = try parseAdditive()
		while true {
			if match(.lt) { lhs = .binary(op: "<", lhs: lhs, rhs: try parseAdditive()) }
			else if match(.lte) { lhs = .binary(op: "<=", lhs: lhs, rhs: try parseAdditive()) }
			else if match(.gt) { lhs = .binary(op: ">", lhs: lhs, rhs: try parseAdditive()) }
			else if match(.gte) { lhs = .binary(op: ">=", lhs: lhs, rhs: try parseAdditive()) }
			else { break }
		}
		return lhs
	}

	private func parseAdditive() throws -> DSLExpr {
		var lhs = try parseMultiplicative()
		while true {
			if match(.plus) { lhs = .binary(op: "+", lhs: lhs, rhs: try parseMultiplicative()) }
			else if match(.minus) { lhs = .binary(op: "-", lhs: lhs, rhs: try parseMultiplicative()) }
			else { break }
		}
		return lhs
	}

	private func parseMultiplicative() throws -> DSLExpr {
		var lhs = try parseUnary()
		while true {
			if match(.star) { lhs = .binary(op: "*", lhs: lhs, rhs: try parseUnary()) }
			else if match(.slash) { lhs = .binary(op: "/", lhs: lhs, rhs: try parseUnary()) }
			else { break }
		}
		return lhs
	}

	private func parseUnary() throws -> DSLExpr {
		if match(.minus) { return .unary(op: "-", operand: try parseUnary()) }
		if match(.not) { return .unary(op: "!", operand: try parseUnary()) }
		return try parsePostfix()
	}

	private func parsePostfix() throws -> DSLExpr {
		var expr = try parsePrimary()
		while true {
			if match(.dot) {
				let name = try expectAnyIdentifier()
				expr = .member(base: expr, name: name)
			} else if match(.lparen) {
				var args: [DSLExpr] = []
				if !check(.rparen) {
					repeat {
						args.append(try parseExpr())
					} while match(.comma)
				}
				try expect(.rparen)
				expr = .call(callee: expr, args: args)
			} else {
				break
			}
		}
		return expr
	}

	private func parsePrimary() throws -> DSLExpr {
		if checkIdentifier("average") {
			return try parseReduce()
		}
		if checkIdentifier("percell") {
			return try parsePercell()
		}
		switch peek() {
			case .number(let text):
				pos += 1
				return .number(text)
			case .identifier(let name):
				pos += 1
				return .identifier(tryFoldGenericSuffix(name))
			case .param(let name):
				pos += 1
				return .param(name)
			case .lparen:
				pos += 1
				let inner = try parseExpr()
				try expect(.rparen)
				return inner
			default:
				throw DSLParseError(message: "Unexpected token \(peek()) in expression")
		}
	}

	/// Folds a trailing `<IDENT>` onto `name` if what follows really looks
	/// like MSL's generic-cast syntax (`as_type<uint3>`) rather than a
	/// less-than comparison -- backtracks otherwise, so `x < y` is
	/// unaffected. The combined text (e.g. "as_type<uint3>") becomes a
	/// single `.identifier`, which then works exactly like any other
	/// passthrough MSL builtin name in call position (see
	/// DSLInterpreter.evaluate's `.call` case) -- no separate AST shape
	/// needed for "generic call".
	private func tryFoldGenericSuffix(_ name: String) -> String {
		guard check(.lt) else { return name }
		let saved = pos
		pos += 1 // consume '<'
		guard case .identifier(let typeName) = peek() else {
			pos = saved
			return name
		}
		pos += 1
		guard match(.gt) else {
			pos = saved
			return name
		}
		return "\(name)<\(typeName)>"
	}

	private func parseReduce() throws -> DSLExpr {
		try expectIdentifier("average")
		try expect(.lparen)
		let variable = try expectAnyIdentifier()
		try expectIdentifier("in")
		let lo = try parseAdditive()
		try expect(.ellipsis)
		let hi = try parseAdditive()
		try expect(.rparen)
		try expect(.lbrace)
		// Each `average` iteration is unrolled inline, so a `break` in here
		// would leave an enclosing loop halfway through an expression.
		let savedLoopDepth = loopDepth
		loopDepth = 0
		scopes.append([variable: false])
		var body: [DSLStmt] = []
		while let stmt = try parseStmt() {
			body.append(stmt)
		}
		let result = try parseExpr()
		scopes.removeLast()
		loopDepth = savedLoopDepth
		try expect(.rbrace)
		return .reduce(variable: variable, lo: lo, hi: hi, body: body, result: result)
	}

	private func parsePercell() throws -> DSLExpr {
		try expectIdentifier("percell")
		try expect(.lparen)
		let at = try expectAnyIdentifier()
		try expect(.comma)
		let spacing = try parseExpr()
		try validateGridSpacing(spacing, param: "percell(\(at), ...)")
		try expect(.rparen)
		try expect(.lbrace)
		// The block may be skipped (its value read from a texture), so no
		// `break` out of an enclosing loop from in here either.
		let savedLoopDepth = loopDepth
		loopDepth = 0
		scopes.append([:])
		var body: [DSLStmt] = []
		while let stmt = try parseStmt() {
			body.append(stmt)
		}
		let result = try parseExpr()
		scopes.removeLast()
		loopDepth = savedLoopDepth
		try expect(.rbrace)
		return .percell(at: at, spacing: spacing, body: body, result: result)
	}

	// MARK: - Token helpers

	private func peek() -> DSLToken {
		tokens[pos]
	}

	private func check(_ token: DSLToken) -> Bool {
		peek() == token
	}

	private func checkIdentifier(_ name: String) -> Bool {
		if case .identifier(let s) = peek() { return s == name }
		return false
	}

	private func match(_ token: DSLToken) -> Bool {
		guard check(token) else { return false }
		pos += 1
		return true
	}

	private func expect(_ token: DSLToken) throws {
		guard match(token) else {
			throw DSLParseError(message: "Expected \(token), found \(peek())")
		}
	}

	private func expectIdentifier(_ name: String) throws {
		guard checkIdentifier(name) else {
			throw DSLParseError(message: "Expected keyword '\(name)', found \(peek())")
		}
		pos += 1
	}

	private func expectAnyIdentifier() throws -> String {
		guard case .identifier(let name) = peek() else {
			throw DSLParseError(message: "Expected identifier, found \(peek())")
		}
		pos += 1
		return name
	}

	/// Reads a raw (optionally negative) numeric literal as a `Double` --
	/// used for `debug slider(min, max)` bounds and a `param` default,
	/// which are plain literals, not full expressions (so `-1.0` here is a
	/// literal sign, not the unary-minus *expression* `parseUnary` handles
	/// elsewhere). Negative literals need their own handling because the
	/// lexer never combines a sign into `.number` itself -- `-1.0` always
	/// tokenizes as `.minus` followed by `.number("1.0")`.
	private func expectNumberLiteral(context: String) throws -> Double {
		let isNegative = match(.minus)
		guard case .number(let text) = peek() else {
			throw DSLParseError(message: "Expected a numeric literal for \(context), found \(peek())")
		}
		pos += 1
		guard let d = Double(text) else {
			throw DSLParseError(message: "Invalid numeric literal '\(text)' for \(context)")
		}
		return isNegative ? -d : d
	}

	/// Accepts either form for a `requires(...)` entry -- a bare
	/// identifier (can't contain '-', same restriction as any other
	/// identifier -- see DSLLexer) or a quoted string (can, matching how
	/// node/module *names* are written). Lets a `requires()` clause name a
	/// hyphenated module like "my-helpers" without needing to rename it.
	///
	/// A leading `::` (two colon tokens) is kept as part of the returned
	/// name -- `::lighting` / `::"my-helpers"` -- and tells DSLLibrary.scan
	/// to skip this file's own root and look only in the roots scanned
	/// before it (the bundled library, for a user node).
	private func expectIdentifierOrString() throws -> String {
		if check(.colon), pos + 1 < tokens.count, tokens[pos + 1] == .colon {
			pos += 2
			return "::" + (try expectIdentifierOrString())
		}
		if case .string(let name) = peek() {
			pos += 1
			return name
		}
		return try expectAnyIdentifier()
	}

	private func expectString() throws -> String {
		guard case .string(let s) = peek() else {
			throw DSLParseError(message: "Expected a quoted node name, found \(peek())")
		}
		pos += 1
		return s
	}
}

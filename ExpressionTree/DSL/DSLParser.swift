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
//                  ('requires' '(' (IDENT|STRING) (',' (IDENT|STRING))* ')')?
//                  '{' (letStmt | paramStmt)* 'return' expr '}'
//    paramDecl  := IDENT (':' IDENT)?          -- ": fn" marks a sampled child
//    paramStmt  := 'param' '$' IDENT ':' IDENT '=' NUMBER
//                  -- a self-contained default for a `$name` reference,
//                  used when nothing external supplies one
//    moduleDecl := 'module' STRING '{' funcDecl* '}'
//    funcDecl   := 'func' IDENT '(' (IDENT ':' IDENT (',' IDENT ':' IDENT)*)? ')'
//                  '->' IDENT '{' letStmt* 'return' expr '}'
//    packageDecl := 'package' STRING          -- a whole file's content
//    letStmt    := 'let' IDENT (':' IDENT)? '=' expr
//    expr       := ternary
//    ternary    := or ('?' expr ':' expr)?
//    or         := and ('||' and)*
//    and        := equality ('&&' equality)*
//    equality   := comparison (('=='|'!=') comparison)*
//    comparison := additive (('<'|'<='|'>'|'>=') additive)*
//    additive   := multiplicative (('+'|'-') multiplicative)*
//    multiplicative := unary (('*'|'/') unary)*
//    unary      := ('-'|'!')? postfix
//    postfix    := primary ('.' IDENT | '(' argList ')')*
//    primary    := NUMBER | IDENT | '$' IDENT | '(' expr ')' | reduceExpr
//    reduceExpr := 'average' '(' IDENT 'in' expr '...' expr ')'
//                  '{' letStmt* expr '}'
//

struct DSLParseError: Error, CustomStringConvertible {
	let message: String
	var description: String { message }
}

final class DSLParser {
	private let tokens: [DSLToken]
	private var pos = 0

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
		var body: [DSLLetStmt] = []
		var paramDefaults: [String: DSLParamValue] = [:]
		while checkIdentifier("let") || checkIdentifier("param") {
			if checkIdentifier("param") {
				let (paramName, value) = try parseParamDefaultStmt()
				paramDefaults[paramName] = value
			} else {
				body.append(try parseLetStmt())
			}
		}
		try expectIdentifier("return")
		let returnExpr = try parseExpr()
		try expect(.rbrace)
		try expect(.eof)

		return DSLTemplate(name: name, params: params, requires: requires, paramDefaults: paramDefaults, body: body, returnExpr: returnExpr)
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
		var body: [DSLLetStmt] = []
		while checkIdentifier("let") {
			body.append(try parseLetStmt())
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

	private func parseParamDefaultStmt() throws -> (name: String, value: DSLParamValue) {
		try expectIdentifier("param")
		guard case .param(let name) = peek() else {
			throw DSLParseError(message: "Expected '$name' after 'param', found \(peek())")
		}
		pos += 1
		try expect(.colon)
		let type = try expectAnyIdentifier()
		try expect(.assign)
		guard case .number(let text) = peek() else {
			throw DSLParseError(message: "Expected a numeric literal default for param '$\(name)', found \(peek())")
		}
		pos += 1

		switch type {
			case "float":
				guard let d = Double(text) else {
					throw DSLParseError(message: "Invalid float literal '\(text)' for param '$\(name)'")
				}
				return (name, .float(ComponentType(d)))
			case "int":
				guard let i = Int(text) else {
					throw DSLParseError(message: "Invalid int literal '\(text)' for param '$\(name)'")
				}
				return (name, .int(i))
			default:
				throw DSLParseError(message: "Unknown param type '\(type)' for '$\(name)' -- expected 'float' or 'int'")
		}
	}

	private func parseParamDecl() throws -> DSLParam {
		let name = try expectAnyIdentifier()
		var isFunction = false
		if match(.colon) {
			let role = try expectAnyIdentifier()
			guard role == "fn" || role == "value" else {
				throw DSLParseError(message: "Unknown param role '\(role)' for '\(name)' -- expected 'fn' or 'value'")
			}
			isFunction = role == "fn"
		}
		return DSLParam(name: name, isFunction: isFunction)
	}

	private func parseLetStmt() throws -> DSLLetStmt {
		try expectIdentifier("let")
		let name = try expectAnyIdentifier()
		var type: String? = nil
		if match(.colon) {
			type = try expectAnyIdentifier()
		}
		try expect(.assign)
		let value = try parseExpr()
		return DSLLetStmt(name: name, type: type, value: value)
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
		var lhs = try parseEquality()
		while match(.and) {
			lhs = .binary(op: "&&", lhs: lhs, rhs: try parseEquality())
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
		switch peek() {
			case .number(let text):
				pos += 1
				return .number(text)
			case .identifier(let name):
				pos += 1
				return .identifier(name)
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
		var body: [DSLLetStmt] = []
		while checkIdentifier("let") {
			body.append(try parseLetStmt())
		}
		let result = try parseExpr()
		try expect(.rbrace)
		return .reduce(variable: variable, lo: lo, hi: hi, body: body, result: result)
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

	/// Accepts either form for a `requires(...)` entry -- a bare
	/// identifier (can't contain '-', same restriction as any other
	/// identifier -- see DSLLexer) or a quoted string (can, matching how
	/// node/module *names* are written). Lets a `requires()` clause name a
	/// hyphenated module like "my-helpers" without needing to rename it.
	private func expectIdentifierOrString() throws -> String {
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

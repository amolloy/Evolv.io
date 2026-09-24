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
//    nodeDecl   := 'node' STRING '(' paramDecl (',' paramDecl)* ')'
//                  ('requires' '(' IDENT (',' IDENT)* ')')?
//                  '{' letStmt* 'return' expr '}'
//    paramDecl  := IDENT (':' IDENT)?          -- ": fn" marks a sampled child
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
					requires.append(try expectAnyIdentifier())
				} while match(.comma)
			}
			try expect(.rparen)
		}

		try expect(.lbrace)
		var body: [DSLLetStmt] = []
		while checkIdentifier("let") {
			body.append(try parseLetStmt())
		}
		try expectIdentifier("return")
		let returnExpr = try parseExpr()
		try expect(.rbrace)
		try expect(.eof)

		return DSLTemplate(name: name, params: params, requires: requires, body: body, returnExpr: returnExpr)
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

	private func expectString() throws -> String {
		guard case .string(let s) = peek() else {
			throw DSLParseError(message: "Expected a quoted node name, found \(peek())")
		}
		pos += 1
		return s
	}
}

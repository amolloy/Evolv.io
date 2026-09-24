//
//  DSLLexer.swift
//  Evolv.io
//
//  Spike: tokenizer for a small readable-text format that compiles to the
//  same MSL a hand-written Node._emitMSL produces today (see
//  DSLCodegenNode.swift for the "why" -- this exists to answer "is a DSL
//  for these definitions actually more readable, and can a hand-rolled
//  parser handle the hard cases (nested-function sampling, resource
//  requirements, a dynamic tap-count loop)?" before committing to porting
//  every node to it).
//
//  Deliberately hand-rolled rather than built on an SPM parsing package --
//  the grammar (C-like expressions, no operator precedence surprises, no
//  need for backtracking) is small enough that a recursive-descent parser
//  is less code and less indirection than wiring up a combinator library
//  would be. Revisit if the grammar grows real complexity (e.g. custom
//  operators, significant whitespace).
//

enum DSLToken: Equatable {
	case identifier(String)
	case param(String)
	case number(String)
	case string(String)
	case lparen, rparen, lbrace, rbrace
	case comma, colon, dot, ellipsis, question
	case plus, minus, star, slash
	case assign, eq, neq, lt, lte, gt, gte
	case and, or, not
	case eof
}

struct DSLLexError: Error, CustomStringConvertible {
	let message: String
	var description: String { message }
}

final class DSLLexer {
	private let chars: [Character]
	private var pos = 0

	init(_ source: String) {
		chars = Array(source)
	}

	func tokenize() throws -> [DSLToken] {
		var tokens: [DSLToken] = []
		while true {
			skipWhitespaceAndComments()
			guard let c = peek() else {
				tokens.append(.eof)
				break
			}
			if c.isLetter || c == "_" {
				tokens.append(.identifier(lexIdentifier()))
			} else if c.isNumber {
				tokens.append(.number(lexNumber()))
			} else if c == "$" {
				pos += 1
				tokens.append(.param(lexIdentifier()))
			} else if c == "\"" {
				tokens.append(.string(try lexString()))
			} else {
				tokens.append(try lexPunctuation())
			}
		}
		return tokens
	}

	private func peek(_ offset: Int = 0) -> Character? {
		let i = pos + offset
		return i < chars.count ? chars[i] : nil
	}

	private func advance() -> Character {
		let c = chars[pos]
		pos += 1
		return c
	}

	private func skipWhitespaceAndComments() {
		while let c = peek() {
			if c.isWhitespace {
				pos += 1
				continue
			}
			if c == "/" && peek(1) == "/" {
				while let c2 = peek(), c2 != "\n" { pos += 1 }
				continue
			}
			break
		}
	}

	private func lexIdentifier() -> String {
		var s = ""
		while let c = peek(), c.isLetter || c.isNumber || c == "_" {
			s.append(advance())
		}
		return s
	}

	private func lexNumber() -> String {
		var s = ""
		while let c = peek(), c.isNumber { s.append(advance()) }
		if peek() == ".", let n = peek(1), n.isNumber {
			s.append(advance())
			while let c = peek(), c.isNumber { s.append(advance()) }
		}
		if let e = peek(), e == "e" || e == "E" {
			var lookahead = 1
			if let sign = peek(1), sign == "+" || sign == "-" { lookahead = 2 }
			if let d = peek(lookahead), d.isNumber {
				s.append(advance())
				if peek() == "+" || peek() == "-" { s.append(advance()) }
				while let c = peek(), c.isNumber { s.append(advance()) }
			}
		}
		return s
	}

	private func lexString() throws -> String {
		pos += 1 // opening quote
		var s = ""
		while let c = peek(), c != "\"" {
			s.append(advance())
		}
		guard peek() == "\"" else {
			throw DSLLexError(message: "Unterminated string literal")
		}
		pos += 1 // closing quote
		return s
	}

	private func lexPunctuation() throws -> DSLToken {
		let c = advance()
		switch c {
			case "(": return .lparen
			case ")": return .rparen
			case "{": return .lbrace
			case "}": return .rbrace
			case ",": return .comma
			case ":": return .colon
			case "?": return .question
			case "+": return .plus
			case "-": return .minus
			case "*": return .star
			case "/": return .slash
			case ".":
				if peek() == ".", peek(1) == "." {
					pos += 2
					return .ellipsis
				}
				return .dot
			case "=":
				if peek() == "=" { pos += 1; return .eq }
				return .assign
			case "!":
				if peek() == "=" { pos += 1; return .neq }
				return .not
			case "<":
				if peek() == "=" { pos += 1; return .lte }
				return .lt
			case ">":
				if peek() == "=" { pos += 1; return .gte }
				return .gt
			case "&":
				guard peek() == "&" else { throw DSLLexError(message: "Unexpected '&'; did you mean '&&'?") }
				pos += 1
				return .and
			case "|":
				guard peek() == "|" else { throw DSLLexError(message: "Unexpected '|'; did you mean '||'?") }
				pos += 1
				return .or
			default:
				throw DSLLexError(message: "Unexpected character '\(c)'")
		}
	}
}

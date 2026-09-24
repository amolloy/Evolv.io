//
//  LispParser.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import os

public final class Parser {
    private let registry = NodeRegistry.shared
    private static let logger = Logger(subsystem: "com.amolloy.ExpressionTree", category: "Parser")

    public init() {}

	public func parse(_ expression: String) throws(ParseError) -> any Node {
        do throws(ParseError) {
            var tokens = tokenize(expression)
            guard !tokens.isEmpty else {
                throw ParseError.unexpectedEndOfInput(expression: expression, expected: "an expression")
            }
            return try parse(tokens: &tokens, expression: expression)
        } catch {
            // Logged once here, at the top of the recursion, rather than at
            // each throw site below -- every case already carries the full
            // `expression`, so there's nothing more to add by logging on
            // the way out of every stack frame too.
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

	private func tokenize(_ expression: String) -> [String] {
		let pattern = #"(#\(|\(|\)|[^\s\(\)]+)"#

		do {
			let regex = try Regex(pattern)
			let matches = expression.matches(of: regex)

			return matches.map { expression[$0.range].lowercased() }
		} catch {
			Self.logger.error("Regex pattern failed: \(String(describing: error), privacy: .public). Falling back to simple split.")
			return expression.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
		}
	}

	private func parse(tokens: inout [String], expression: String) throws(ParseError) -> any Node {
        guard let token = tokens.first else {
            throw ParseError.unexpectedEndOfInput(
                expression: expression,
                expected: "an expression, a function call, or a number"
            )
        }

		tokens.removeFirst()

        switch token {
        case "(":
            return try parseFunctionCall(tokens: &tokens, expression: expression)
            
        case "#(":
            return try parseConstantTriplet(tokens: &tokens, expression: expression)
            
        default:
            return try makeTerminalNode(token: token, expression: expression)
        }
    }
    
	private func parseFunctionCall(tokens: inout [String], expression: String) throws(ParseError) -> any Node {
        guard let functionName = tokens.first else {
            throw ParseError.unexpectedEndOfInput(expression: expression, expected: "a function name after '('")
        }
        tokens.removeFirst()
        
		var children: [any Node] = []
        while let nextToken = tokens.first, nextToken != ")" {
            children.append(try parse(tokens: &tokens, expression: expression))
        }
        
        guard tokens.first == ")" else {
            throw ParseError.expectedClosingParenthesis(
                expression: expression,
                found: tokens.first.map { "'\($0)'" } ?? "end of input"
            )
        }
        tokens.removeFirst() // Consume the ')'
        
        return try registry.makeNode(name: functionName, children: children, expression: expression)
    }

	private func parseConstantTriplet(tokens: inout [String], expression: String) throws(ParseError) -> any Node {
        var values: [Double] = []
        for index in 0..<3 {
            guard let token = tokens.first else {
                throw ParseError.unexpectedEndOfInput(
                    expression: expression,
                    expected: "a number for component \(index + 1) of 3 in a #(...) triplet"
                )
            }
            guard let value = Double(token) else {
                throw ParseError.invalidNumberLiteral(
                    token: token,
                    expression: expression,
                    context: "component \(index + 1) of 3 in a #(...) triplet"
                )
            }
            tokens.removeFirst()
            values.append(value)
        }
        
        guard tokens.first == ")" else {
            throw ParseError.expectedClosingParenthesis(
                expression: expression,
                found: tokens.first.map { "'\($0)'" } ?? "end of input"
            )
        }
        tokens.removeFirst() // Consume the ')'
        
		return ConstantTriplet(Value(values[0], values[1], values[2]))
    }

	private func makeTerminalNode(token: String, expression: String) throws(ParseError) -> any Node {
        if let value = Double(token) {
            // It's a bare number, so it's a ConstantNode. Bare numbers and
            // #(...) triplets are the two cases that can never be
            // DSL-defined nodes -- they're literal syntax the tokenizer
            // recognizes directly, not a name+children shape the registry
            // could look up (there's no "body" to write for a literal;
            // its value comes from the parse site, not a formula).
            return Constant(value)
        }

        // Anything else -- including "x"/"y", which look like bare
        // variables here but are genuinely registry-defined nodes with
        // zero children (see Evolv.io/Resources/BundledNodes/{x,y}.evolvnode).
        return try registry.makeNode(name: token, children: [], expression: expression)
    }
}

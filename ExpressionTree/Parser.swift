//
//  LispParser.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

public final class Parser {
    private let registry = NodeRegistry.shared

    public init() {}

	public func parse(_ expression: String) throws -> any Node {
        var tokens = tokenize(expression)
        guard !tokens.isEmpty else {
            throw ParseError.unexpectedEndOfInput
        }
        return try parse(tokens: &tokens)
    }

	private func tokenize(_ expression: String) -> [String] {
		let pattern = #"(#\(|\(|\)|[^\s\(\)]+)"#

		do {
			let regex = try Regex(pattern)
			let matches = expression.matches(of: regex)

			return matches.map { expression[$0.range].lowercased() }
		} catch {
			print("Regex pattern failed: \(error). Falling back to simple split.")
			return expression.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
		}
	}

	private func parse(tokens: inout [String]) throws -> any Node {
        guard let token = tokens.first else {
            throw ParseError.unexpectedEndOfInput
        }

		tokens.removeFirst()

        switch token {
        case "(":
            return try parseFunctionCall(tokens: &tokens)
            
        case "#(":
            return try parseConstantTriplet(tokens: &tokens)
            
        default:
            return try makeTerminalNode(token: token)
        }
    }
    
	private func parseFunctionCall(tokens: inout [String]) throws -> any Node {
        guard let functionName = tokens.first else { throw ParseError.unexpectedEndOfInput }
        tokens.removeFirst()
        
		var children: [any Node] = []
        while let nextToken = tokens.first, nextToken != ")" {
            children.append(try parse(tokens: &tokens))
        }
        
        guard tokens.first == ")" else { throw ParseError.expectedClosingParenthesis }
        tokens.removeFirst() // Consume the ')'
        
        return try registry.makeNode(name: functionName, children: children)
    }

	private func parseConstantTriplet(tokens: inout [String]) throws -> any Node {
        var values: [Double] = []
        for _ in 0..<3 {
            guard let token = tokens.first, let value = Double(token) else {
                throw ParseError.invalidToken("Expected a number for triplet.")
            }
            tokens.removeFirst()
            values.append(value)
        }
        
        guard tokens.first == ")" else { throw ParseError.expectedClosingParenthesis }
        tokens.removeFirst() // Consume the ')'
        
		return ConstantTriplet(Value(values[0], values[1], values[2]))
    }

	private func makeTerminalNode(token: String) throws -> any Node {
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
        return try registry.makeNode(name: token, children: [])
    }
}

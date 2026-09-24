//
//  NodeRegistry.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//


public final class NodeRegistry {
	public typealias NodeConstructor = ([any Node]) throws -> any Node

    public let registry: [String: NodeConstructor]

    public init() {
		let nodeTypes: [any Node.Type] = [
			Abs.self,
			Add.self,
			And.self,
			Bump.self,
			Dissolve.self,
			Div.self,
			BWNoise.self,
			ColorGradient.self,
			ColorGradientCurvature.self,
			ColorNoise.self,
			Constant.self,
			ConstantTriplet.self,
			GradientDirection.self,
			HSVToRGB.self,
			If.self,
			Invert.self,
			Log.self,
			Mod.self,
			Mult.self,
			RotateVector.self,
			Round.self,
			VariableX.self,
			VariableY.self,
			WarpedBWNoise.self,
			WarpedColorNoise.self,
		]

        // Programmatically build the registry from the list of types.
        // No giant switch statement needed!
        var builtRegistry: [String: NodeConstructor] = [:]
        for type in nodeTypes {
            builtRegistry[type.name] = type.init
        }

        // "dsl-"-prefixed spike registrations: the same math as "mod" and
        // "color-grad" above, but emitted by interpreting a parsed
        // DSLTemplate (see DSLCodegenNode.swift) instead of a hand-written
        // _emitMSL. Registered under distinct names, not as replacements,
        // so both can be picked from ContentView's sample list side by
        // side. See DSLSampleDefinitions.swift for the source text.
        builtRegistry["dsl-mod"] = { children in
            DSLCodegenNode(template: DSLSampleDefinitions.modTemplate, children: children)
        }
        builtRegistry["dsl-color-grad"] = { children in
            DSLCodegenNode(template: DSLSampleDefinitions.colorGradTemplate,
                            params: DSLSampleDefinitions.colorGradParams,
                            children: children)
        }

        self.registry = builtRegistry
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

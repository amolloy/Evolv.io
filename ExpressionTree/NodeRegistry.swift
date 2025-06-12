//
//  NodeRegistry.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//


public final class NodeRegistry {
    public typealias NodeConstructor = ([Node]) throws -> Node

    public let registry: [String: NodeConstructor]

    public init() {
        let nodeTypes: [Node.Type] = [
			Abs.self,
			And.self,
			BWNoise.self,
			ColorNoise.self,
			Constant.self,
			GradientDirection.self,
			Mod.self,
			Mult.self,
			VariableX.self,
			VariableY.self,
			WarpedColorNoise.self,
		]

        // Programmatically build the registry from the list of types.
        // No giant switch statement needed!
        var builtRegistry: [String: NodeConstructor] = [:]
        for type in nodeTypes {
            builtRegistry[type.name] = type.init
        }
        self.registry = builtRegistry
    }
    
    public func makeNode(name: String, children: [Node]) throws -> Node {
        guard let constructor = registry[name] else {
            throw ParseError.unknownFunction(name)
        }
        return try constructor(children)
    }
}

enum ParseError: Error {
	case unknownFunction(String)
}

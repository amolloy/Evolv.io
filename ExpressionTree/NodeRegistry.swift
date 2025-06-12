public final class NodeRegistry {
    // The type for our factory's constructor closures.
    public typealias NodeConstructor = ([Node]) throws -> Node

    /// The dictionary mapping a Lisp name to a constructor.
    public let registry: [String: NodeConstructor]

    public init() {
        // This is the ONLY manual list you need to maintain.
        // It's clean, simple, and type-checked by the compiler.
        let nodeTypes: [ParsableNode.Type] = [
            MultNode.self,
            AddNode.self,
            GradientDirectionNode.self,
            // ... add MyNewNode.self here when you create it ...
        ]

        // Programmatically build the registry from the list of types.
        // No giant switch statement needed!
        var builtRegistry: [String: NodeConstructor] = [:]
        for type in nodeTypes {
            builtRegistry[type.lispName] = type.init
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
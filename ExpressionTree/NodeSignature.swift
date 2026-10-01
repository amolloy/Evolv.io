//
//  NodeSignature.swift
//  Evolv.io
//
//  What the random expression generator needs to know about a node without
//  building one: its arity, the argument types it prefers, and what it
//  returns. Comes from a `.evolvnode` file's param list (`p1: scalar`,
//  `color: vector`) and optional `-> scalar`/`-> vector` output type.
//
//  The types are hints only. Every child is still a float3 at codegen time,
//  a scalar is a broadcast triplet, and nodes coerce whatever they get (see
//  Documentation/EvolvNodeFormat.md). Sims' published genotypes nearly
//  always pass the preferred type anyway -- see
//  Documentation/RandomGeneration.md.
//

public enum NodeValueType: String, Sendable {
	case scalar
	case vector
}

public struct NodeSignature: Sendable {
	public let name: String
	/// One entry per child, in order. nil means either type.
	public let argumentTypes: [NodeValueType?]
	/// nil means the node follows its untyped children: vector if any of
	/// them is, otherwise scalar.
	public let outputType: NodeValueType?
	/// From `nonconst` in the `.evolvnode` file: a no-argument node that
	/// asked not to be treated as a terminal.
	public let isNonconst: Bool

	public init(name: String, argumentTypes: [NodeValueType?], outputType: NodeValueType?, isNonconst: Bool = false) {
		self.name = name
		self.argumentTypes = argumentTypes
		self.outputType = outputType
		self.isNonconst = isNonconst
	}

	public var arity: Int { argumentTypes.count }

	/// A node with no arguments is a terminal -- the generator's "variable"
	/// form -- unless it's marked `nonconst`, in which case it's
	/// picked like any other function.
	public var isTerminal: Bool { arity == 0 && !isNonconst }
}

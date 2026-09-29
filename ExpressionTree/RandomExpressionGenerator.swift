//
//  RandomExpressionGenerator.swift
//  Evolv.io
//
//  Builds random genotypes the way Sims describes (1991 §4.1, 1993 §2):
//  pick a function at random, then fill each argument with a random scalar,
//  a random 3-vector, a variable, or another random expression. The only
//  addition is each argument's preferred type from its `.evolvnode` file
//  (see NodeSignature): a scalar slot draws scalars, variables or
//  scalar-returning expressions; a vector slot draws vectors or
//  vector-returning expressions. No per-node weights -- Sims never
//  mentions any. See Documentation/RandomGeneration.md.
//

import Foundation

public indirect enum GeneratedExpression: Equatable, Sendable, CustomStringConvertible {
	case scalar(Double)
	case vector(Double, Double, Double)
	/// A node call. A variable (`x`, `y`) is a call with no arguments.
	case call(String, [GeneratedExpression])

	/// The genotype text, e.g. `(bw-noise 0.2 0.57)`, readable by `Parser`.
	public var description: String {
		switch self {
			case .scalar(let value):
				return Self.format(value)
			case .vector(let r, let g, let b):
				return "#(\(Self.format(r)) \(Self.format(g)) \(Self.format(b)))"
			case .call(let name, let arguments):
				guard !arguments.isEmpty else { return name }
				return "(\(name) \(arguments.map(\.description).joined(separator: " ")))"
		}
	}

	/// Two significant figures, like the constants in Sims' genotypes.
	private static func format(_ value: Double) -> String {
		String(format: "%.2g", value)
	}
}

public struct RandomExpressionGenerator {
	public struct Configuration: Sendable {
		/// Leaves offered as the "variable" form. `z` is for volume
		/// textures, so 2D images use just `x` and `y`.
		public var variables: [String] = ["x", "y"]
		/// How many levels of function calls a tree can have. 2 means the
		/// root call's arguments can be calls, but theirs are leaves, like
		/// Sims' Figure 4h `(grad-direction (bw-noise .15 2) .0 .0)`. 2 gave
		/// first generations too simple to be interesting; Andy found 10
		/// gave the best ones.
		public var maxDepth: Int = 10
		/// Chance an argument is a sub-expression, when depth allows.
		/// Otherwise it's one of the literal/variable forms its type allows,
		/// picked uniformly.
		public var expressionProbability: Double = 0.3
		public var scalarRange: ClosedRange<Double> = -1.0...1.0
		public var vectorComponentRange: ClosedRange<Double> = 0.0...1.0
		/// Node names never picked as functions (the variables above are
		/// excluded automatically).
		public var excludedFunctions: Set<String> = []

		public init() {}
	}

	private enum Form {
		case scalar, vector, variable, expression
	}

	public let configuration: Configuration
	private let functions: [NodeSignature]

	/// `signatures` is normally `NodeRegistry.shared.signatures`. Every node
	/// with at least one argument that isn't excluded is in the function set.
	public init(signatures: [String: NodeSignature], configuration: Configuration = Configuration()) {
		self.configuration = configuration
		let variables = Set(configuration.variables)
		functions = signatures.values
			.filter { $0.arity > 0 && !variables.contains($0.name) && !configuration.excludedFunctions.contains($0.name) }
			// Sorted so a seeded generator gives the same expression on
			// every run, whatever order the dictionary iterates in.
			.sorted { $0.name < $1.name }
	}

	/// A random genotype. The root is always a function call, since Sims
	/// starts by picking a function.
	public func generate<G: RandomNumberGenerator>(using rng: inout G) -> GeneratedExpression {
		randomCall(fitting: nil, depth: 0, using: &rng)
	}

	private func randomCall<G: RandomNumberGenerator>(fitting type: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression {
		let candidates = functions.filter { type == nil || $0.outputType == nil || $0.outputType == type }
		guard let function = candidates.randomElement(using: &rng) else {
			preconditionFailure("RandomExpressionGenerator: no functions to pick from")
		}
		let arguments = function.argumentTypes.map { randomArgument(preferring: $0, depth: depth + 1, using: &rng) }
		return .call(function.name, arguments)
	}

	private func randomArgument<G: RandomNumberGenerator>(preferring type: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression {
		let form: Form
		if depth < configuration.maxDepth && Double.random(in: 0..<1, using: &rng) < configuration.expressionProbability {
			form = .expression
		} else {
			let forms: [Form]
			switch type {
				case .scalar: forms = configuration.variables.isEmpty ? [.scalar] : [.scalar, .variable]
				case .vector: forms = [.vector]
				case nil: forms = configuration.variables.isEmpty ? [.scalar, .vector] : [.scalar, .vector, .variable]
			}
			form = forms.randomElement(using: &rng)!
		}

		switch form {
			case .scalar:
				return .scalar(Double.random(in: configuration.scalarRange, using: &rng))
			case .vector:
				let range = configuration.vectorComponentRange
				return .vector(Double.random(in: range, using: &rng),
							   Double.random(in: range, using: &rng),
							   Double.random(in: range, using: &rng))
			case .variable:
				return .call(configuration.variables.randomElement(using: &rng)!, [])
			case .expression:
				return randomCall(fitting: type, depth: depth, using: &rng)
		}
	}
}

/// A small seedable generator (SplitMix64), so a population can be
/// regenerated from its seed. The system generator can't be seeded.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
	private var state: UInt64

	public init(seed: UInt64) {
		state = seed
	}

	public mutating func next() -> UInt64 {
		state &+= 0x9E3779B97F4A7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		return z ^ (z >> 31)
	}
}

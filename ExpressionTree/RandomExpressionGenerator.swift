//
//  RandomExpressionGenerator.swift
//  Evolv.io
//
//  Builds random genotypes the way Sims describes (1991 §4.1, 1993 §2):
//  pick a function at random, then fill each argument with a random scalar,
//  a random 3-vector, a variable (any node with no arguments), or another
//  random expression. The only
//  addition is each argument's preferred type from its `.evolvnode` file
//  (see NodeSignature): a scalar slot draws scalars, variables or
//  scalar-returning expressions; a vector slot draws vectors or
//  vector-returning expressions. No per-node weights -- Sims never
//  mentions any. See Documentation/RandomGeneration.md.
//

import Foundation

public indirect enum GeneratedExpression: Hashable, Sendable, CustomStringConvertible {
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

	/// The shortest text that reads back as exactly `value`, without a
	/// trailing `.0`, so a parsed genotype prints its constants as written.
	/// Generated and mutated constants are rounded when they're made
	/// (`rounded(_:significantFigures:)`), not here.
	private static func format(_ value: Double) -> String {
		let text = "\(value)"
		return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
	}

	/// `value` to `figures` significant figures, like the constants in
	/// Sims' genotypes (two for new ones, three after a mutation).
	public static func rounded(_ value: Double, significantFigures figures: Int) -> Double {
		Double(String(format: "%.\(figures)g", value)) ?? value
	}
}

public struct RandomExpressionGenerator {
	public struct TerminalWeights: Sendable {
		public var scalar: Double = 1
		public var vector: Double = 1
		/// Shared by every variable that fits the slot, picked uniformly
		/// among them. 3 cut the genotypes with no `x` or `y` from 7.7% to 2.7% of
		/// 5,000; about 65% of terminals are then variables.
		public var variable: Double = 3

		public init(scalar: Double = 1, vector: Double = 1, variable: Double = 3) {
			self.scalar = scalar
			self.vector = vector
			self.variable = variable
		}
	}

	public struct Configuration: Sendable {
		/// No-argument nodes never used as variables. Every other
		/// no-argument node is one, including user-written ones. `z` is for
		/// volume textures, so 2D images use just `x` and `y`. The app
		/// reads this from user defaults (`UserDefaults.randomExcludedVariables`).
		public var excludedVariables: Set<String> = Self.defaultExcludedVariables
		public static let defaultExcludedVariables: Set<String> = ["z"]
		/// How many levels of function calls a tree can have. 2 means the
		/// root call's arguments can be calls, but theirs are leaves, like
		/// Sims' Figure 4h `(grad-direction (bw-noise .15 2) .0 .0)`. 2 gave
		/// first generations too simple to be interesting; Andy found 10
		/// gave the best ones.
		public var maxDepth: Int = 10
		/// Chance one of the root's arguments is a sub-expression. Otherwise
		/// it's one of the literal/variable forms its type allows, picked
		/// uniformly. 0.9 with a decay of 0.5 cut the genotypes with no `x`
		/// or `y` anywhere (always a solid colour) from 23% to 7% of
		/// 5,000, compared with a flat 0.3, and made the biggest trees
		/// smaller.
		public var expressionProbability: Double = 0.9
		/// Each level below the root's arguments multiplies the chance of a
		/// sub-expression by this, so trees are bushy near the top and
		/// thin out into literals and variables lower down. 1 keeps the
		/// same chance at every level.
		public var expressionProbabilityDecay: Double = 0.5
		/// Relative chance of each terminal form, among the forms a slot's
		/// type allows. Weighting variables over constants means fewer
		/// all-constant (solid colour) subtrees.
		public var terminalWeights = TerminalWeights()
		public var scalarRange: ClosedRange<Double> = -1.0...1.0
		public var vectorComponentRange: ClosedRange<Double> = 0.0...1.0
		/// Node names never picked at all, as functions or variables.
		public var excludedFunctions: Set<String> = []
		/// Node names never picked as the root call, though they can still
		/// appear anywhere below it. The app reads this from user defaults
		/// (`UserDefaults.randomExcludedRootNodes`).
		public var excludedRootFunctions: Set<String> = Self.defaultExcludedRootFunctions

		/// Constants, colour triplets and `vector`: a genotype that is just
		/// a flat value or a vector of three sub-expressions isn't
		/// interesting as a whole image. The two literal built-ins are never
		/// a root anyway (the root is always a call); they're listed so the
		/// stored setting reads as Andy described it.
		public static let defaultExcludedRootFunctions: Set<String> = [
			Constant.name, ConstantTriplet.name, "vector",
		]

		public init() {}
	}

	private enum Form {
		case scalar, vector, variable
	}

	public let configuration: Configuration
	let signatures: [String: NodeSignature]
	let functions: [NodeSignature]
	/// The no-argument nodes: by definition terminals, so they're the
	/// "variable" form rather than functions.
	let variables: [NodeSignature]
	let rootFunctions: [NodeSignature]

	/// `signatures` is normally `NodeRegistry.shared.signatures`. Every node
	/// that isn't excluded is either a function or a variable (a terminal:
	/// no arguments, and not marked `nonconst`).
	public init(signatures: [String: NodeSignature], configuration: Configuration = Configuration()) {
		self.configuration = configuration
		self.signatures = signatures
		let nodes = signatures.values
			.filter { !configuration.excludedFunctions.contains($0.name) }
			// Sorted so a seeded generator gives the same expression on
			// every run, whatever order the dictionary iterates in.
			.sorted { $0.name < $1.name }
		functions = nodes.filter { !$0.isTerminal }
		variables = nodes.filter { $0.isTerminal && !configuration.excludedVariables.contains($0.name) }
		rootFunctions = functions.filter { !configuration.excludedRootFunctions.contains($0.name) }
	}

	/// A random genotype. The root is always a function call, since Sims
	/// starts by picking a function, and never one of
	/// `excludedRootFunctions`.
	public func generate<G: RandomNumberGenerator>(using rng: inout G) -> GeneratedExpression {
		randomCall(from: rootFunctions, fitting: nil, depth: 0, using: &rng)
	}

	func randomCall<G: RandomNumberGenerator>(from functions: [NodeSignature], fitting type: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression {
		let candidates = functions.filter { type == nil || $0.outputType == nil || $0.outputType == type }
		guard let function = candidates.randomElement(using: &rng) else {
			preconditionFailure("RandomExpressionGenerator: no functions to pick from")
		}
		let arguments = function.argumentTypes.map { randomArgument(preferring: $0, depth: depth + 1, using: &rng) }
		return .call(function.name, arguments)
	}

	/// `depth` is the argument's depth: 1 for the root's arguments.
	func expressionProbability(atDepth depth: Int) -> Double {
		configuration.expressionProbability * pow(configuration.expressionProbabilityDecay, Double(depth - 1))
	}

	/// Two steps, as Andy suggested: first decide whether the argument is a
	/// sub-expression or a terminal, then `randomTerminal` decides which
	/// terminal.
	func randomArgument<G: RandomNumberGenerator>(preferring type: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression {
		if depth < configuration.maxDepth && Double.random(in: 0..<1, using: &rng) < expressionProbability(atDepth: depth) {
			return randomCall(from: functions, fitting: type, depth: depth, using: &rng)
		}
		return randomTerminal(preferring: type, using: &rng)
	}

	/// A scalar literal, vector literal or variable, whichever the slot's
	/// type allows, picked by `terminalWeights`. A variable fits a slot the
	/// same way a function does, by its output type, so `x` and `y` never
	/// land in a vector slot but a user's vector-valued variable could.
	func randomTerminal<G: RandomNumberGenerator>(preferring type: NodeValueType?, using rng: inout G) -> GeneratedExpression {
		let weights = configuration.terminalWeights
		let fittingVariables = variables.filter { type == nil || $0.outputType == nil || $0.outputType == type }
		var forms: [(Form, Double)]
		switch type {
			case .scalar: forms = [(.scalar, weights.scalar), (.variable, weights.variable)]
			case .vector: forms = [(.vector, weights.vector), (.variable, weights.variable)]
			case nil: forms = [(.scalar, weights.scalar), (.vector, weights.vector), (.variable, weights.variable)]
		}
		if fittingVariables.isEmpty {
			forms.removeAll { $0.0 == .variable }
		}
		// If everything left is weighted zero (say, a vector slot with the
		// vector weight at 0 and no vector variables), the literal of the
		// slot's type is the only sensible terminal.
		var form: Form = type == .vector ? .vector : .scalar
		let total = forms.map(\.1).reduce(0, +)
		if total > 0 {
			var pick = Double.random(in: 0..<total, using: &rng)
			for (candidate, weight) in forms {
				if pick < weight {
					form = candidate
					break
				}
				pick -= weight
			}
		}

		switch form {
			case .scalar:
				return .scalar(Self.literal(Double.random(in: configuration.scalarRange, using: &rng)))
			case .vector:
				let range = configuration.vectorComponentRange
				return .vector(Self.literal(Double.random(in: range, using: &rng)),
							   Self.literal(Double.random(in: range, using: &rng)),
							   Self.literal(Double.random(in: range, using: &rng)))
			case .variable:
				return .call(fittingVariables.randomElement(using: &rng)!.name, [])
		}
	}

	/// Two significant figures, like the constants in Sims' genotypes.
	private static func literal(_ value: Double) -> Double {
		GeneratedExpression.rounded(value, significantFigures: 2)
	}
}

extension UserDefaults {
	public static let randomExcludedRootNodesKey = "randomExcludedRootNodes"

	/// Node names `RandomExpressionGenerator` never picks as the root. No UI
	/// edits it; change it with
	/// `defaults write <bundle id> randomExcludedRootNodes -array vector ...`.
	public var randomExcludedRootNodes: Set<String> {
		guard let names = stringArray(forKey: Self.randomExcludedRootNodesKey) else {
			return RandomExpressionGenerator.Configuration.defaultExcludedRootFunctions
		}
		return Set(names)
	}

	public static let randomExcludedVariablesKey = "randomExcludedVariables"

	/// No-argument nodes `RandomExpressionGenerator` never uses as
	/// variables. No UI edits it; change it with
	/// `defaults write <bundle id> randomExcludedVariables -array z ...`.
	public var randomExcludedVariables: Set<String> {
		guard let names = stringArray(forKey: Self.randomExcludedVariablesKey) else {
			return RandomExpressionGenerator.Configuration.defaultExcludedVariables
		}
		return Set(names)
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

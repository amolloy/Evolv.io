//
//  ExpressionMutator.swift
//  Evolv.io
//
//  Asexual reproduction: a child genotype made from one parent by Sims'
//  recursive mutation scheme (1991 §4.2, 1993 §2.1). The parent tree is
//  walked from the root and each node in turn may mutate, with a chance
//  scaled inversely to the parent's size so big parents stay stable. A
//  node that mutates gets one of his seven kinds of mutation:
//
//  1. become a new random expression
//  2. a scalar has a random amount added
//  3. a vector has random amounts added to each element
//  4. a function becomes a different function, its arguments adjusted to
//     the new number and types (a variable becomes another variable)
//  5. become the argument of a new random function
//  6. a function is replaced by one of its own arguments
//  7. become a copy of another node of the parent
//
//  Replacements respect the same preferred slot types the generator uses
//  (NodeSignature). See Documentation/Mutation.md.
//

import Foundation

extension GeneratedExpression {
	public struct TextError: Error, CustomStringConvertible, Sendable {
		public let description: String
	}

	/// Reads genotype text into a tree: numbers, `#(r g b)`, `(name
	/// arguments...)` and bare names (variables). Lower-cased, like
	/// `Parser`. Only the syntax is checked; whether the names are real
	/// nodes is up to the caller (`ExpressionMutator.unknownNodes(in:)`).
	public init(parsing text: String) throws {
		let token = try Regex(#"#\(|\(|\)|[^\s()]+"#)
		var tokens = text.matches(of: token).map { text[$0.range].lowercased() }[...]
		self = try Self.read(&tokens, text: text)
		if let extra = tokens.first {
			throw TextError(description: "Unexpected '\(extra)' after the end of the expression \"\(text)\".")
		}
	}

	private static func read(_ tokens: inout ArraySlice<String>, text: String) throws -> GeneratedExpression {
		guard let token = tokens.popFirst() else {
			throw TextError(description: "The expression \"\(text)\" ends too soon.")
		}
		switch token {
			case "(":
				guard let name = tokens.popFirst(), !["(", ")", "#("].contains(name), Double(name) == nil else {
					throw TextError(description: "Expected a function name after '(' in \"\(text)\".")
				}
				var arguments: [GeneratedExpression] = []
				while let next = tokens.first, next != ")" {
					arguments.append(try read(&tokens, text: text))
				}
				guard tokens.popFirst() == ")" else {
					throw TextError(description: "Missing ')' in \"\(text)\".")
				}
				return .call(name, arguments)
			case "#(":
				var components: [Double] = []
				for _ in 0..<3 {
					guard let next = tokens.popFirst(), let value = Double(next) else {
						throw TextError(description: "A #(...) vector needs three numbers in \"\(text)\".")
					}
					components.append(value)
				}
				guard tokens.popFirst() == ")" else {
					throw TextError(description: "Missing ')' after a #(...) vector in \"\(text)\".")
				}
				return .vector(components[0], components[1], components[2])
			case ")":
				throw TextError(description: "Unexpected ')' in \"\(text)\".")
			default:
				if let value = Double(token) {
					return .scalar(value)
				}
				return .call(token, [])
		}
	}

	/// Every node: calls, variables and literals (a vector literal is one).
	public var nodeCount: Int {
		guard case .call(_, let arguments) = self else { return 1 }
		return 1 + arguments.reduce(0) { $0 + $1.nodeCount }
	}

	/// Every node with its path (argument indices from the root), root first.
	func subtrees(at path: [Int] = []) -> [(path: [Int], expression: GeneratedExpression)] {
		var result = [(path, self)]
		if case .call(_, let arguments) = self {
			for (index, argument) in arguments.enumerated() {
				result += argument.subtrees(at: path + [index])
			}
		}
		return result
	}

	var isCallWithArguments: Bool {
		if case .call(_, let arguments) = self { return !arguments.isEmpty }
		return false
	}

	/// Every call name in the tree, variables included.
	public var callNames: Set<String> {
		guard case .call(let name, let arguments) = self else { return [] }
		return arguments.reduce(into: [name]) { $0.formUnion($1.callNames) }
	}
}

public struct ExpressionMutator {
	public enum Kind: String, Sendable, CaseIterable {
		/// 1: a new random expression, built like a first-generation one.
		case newExpression = "new-expression"
		/// 2: a scalar plus a Gaussian amount proportional to its size.
		case adjustScalar = "adjust-scalar"
		/// 3: each element of a vector plus a Gaussian amount.
		case adjustVector = "adjust-vector"
		/// 4: a different function, keeping the arguments that still fit.
		case swapFunction = "swap-function"
		/// 4 for a variable (a function with no arguments): another variable.
		case swapVariable = "swap-variable"
		/// 5: the node becomes an argument of a new random function.
		case wrap
		/// 6: a function is replaced by one of its arguments.
		case hoist
		/// 7: a copy of another node of the parent.
		case copy
	}

	/// Relative chance of each kind, among those that apply to the node.
	/// `adjust` is 2 or 3, `swap` is 4 (function or variable).
	public struct Weights: Sendable {
		public var newExpression: Double
		public var adjust: Double
		public var swap: Double
		public var wrap: Double
		public var hoist: Double
		public var copy: Double

		public init(newExpression: Double = 0, adjust: Double = 0, swap: Double = 0, wrap: Double = 0, hoist: Double = 0, copy: Double = 0) {
			self.newExpression = newExpression
			self.adjust = adjust
			self.swap = swap
			self.wrap = wrap
			self.hoist = hoist
			self.copy = copy
		}
	}

	public struct Configuration: Sendable {
		/// Sims scales the overall mutation frequency inversely to the
		/// parent's size: each node mutates with chance
		/// `mutationsPerChild / nodeCount`, so a child averages this many
		/// mutations whatever the parent's size.
		public var mutationsPerChild: Double = 1
		/// Sims wants shrinking slightly more likely than growing, so
		/// hoist (6) outweighs wrap (5). Over 2,000 children of each of
		/// the six published genotypes, these give 29% of children
		/// smaller than the parent, 28% bigger and a mean change of -1.7
		/// nodes (wrap 1.5 gave 27% smaller, 33% bigger).
		public var callWeights = Weights(newExpression: 1, swap: 3, wrap: 1, hoist: 2, copy: 1)
		public var variableWeights = Weights(newExpression: 1, swap: 2, wrap: 1, copy: 1)
		/// Literals are mostly nudged: Sims' constants (15.5, 1.86, -31)
		/// look like the sum of many small adjustments.
		public var literalWeights = Weights(newExpression: 1, adjust: 5, wrap: 1, copy: 1)
		/// A scalar moves by a Gaussian with this standard deviation times
		/// its own size (at least `scalarSigmaFloor`), so 15.5 moves by
		/// about 4 and 0.2 by about 0.13. Proportional, as Andy chose
		/// (2026-10-03), rather than Sims' flat ±d for parameter sets.
		public var scalarSigma: Double = 0.25
		public var scalarSigmaFloor: Double = 0.5
		/// Standard deviation added to each vector element. No clamp: Sims'
		/// vectors include -0.14 and 1.06.
		public var vectorSigma: Double = 0.1
		/// Sims threw away offspring he estimated would be too slow. For
		/// now that's a size cap: a child over `maxGrowth` times the
		/// parent's node count (but at least `minimumMaxNodes`, and at
		/// most `absoluteMaxNodes`) is redrawn. Without the absolute cap,
		/// 100 unselected generations reached nearly 1,000 nodes; the
		/// biggest first-generation trees are about 560.
		public var maxGrowth: Double = 2
		public var minimumMaxNodes: Int = 200
		public var absoluteMaxNodes: Int = 1000
		/// Draws before giving up on a child that changes something and
		/// fits the size cap.
		public var maxAttempts: Int = 1000

		public init() {}
	}

	public struct Mutation: Sendable, Equatable {
		public let kind: Kind
		/// Argument indices from the root to the node that mutated.
		public let path: [Int]
		public let before: GeneratedExpression
		public let after: GeneratedExpression
	}

	public struct Child: Sendable {
		public let expression: GeneratedExpression
		/// In the order the walk met them, root first.
		public let mutations: [Mutation]
	}

	/// Builds new random material, and supplies the function set,
	/// variables, excluded roots and signatures.
	public let generator: RandomExpressionGenerator
	public let configuration: Configuration

	public init(generator: RandomExpressionGenerator, configuration: Configuration = Configuration()) {
		self.generator = generator
		self.configuration = configuration
	}

	/// Names in `expression` that aren't registered nodes.
	public func unknownNodes(in expression: GeneratedExpression) -> Set<String> {
		expression.callNames.filter { generator.signatures[$0] == nil }
	}

	/// A parent already over the absolute cap (written by hand, say) can
	/// still have children no bigger than itself.
	public func maxNodes(forParent parent: GeneratedExpression) -> Int {
		let grown = max(configuration.minimumMaxNodes, Int((Double(parent.nodeCount) * configuration.maxGrowth).rounded(.up)))
		return max(parent.nodeCount, min(configuration.absoluteMaxNodes, grown))
	}

	/// A child that differs from `parent` and fits the size cap, redrawn
	/// as often as needed (a draw with no mutations at all is common: about
	/// a third at one mutation per child). nil after `maxAttempts` draws.
	public func mutate<G: RandomNumberGenerator>(_ parent: GeneratedExpression, using rng: inout G) -> Child? {
		let limit = maxNodes(forParent: parent)
		let probability = configuration.mutationsPerChild / Double(parent.nodeCount)
		let parentSubtrees = parent.subtrees().map(\.expression)
		for _ in 0..<configuration.maxAttempts {
			var walk = Walk(mutator: self, probability: probability, parentSubtrees: parentSubtrees)
			let child = walk.visit(parent, slot: nil, depth: 0, path: [], using: &rng)
			if child != parent && child.nodeCount <= limit {
				return Child(expression: child, mutations: walk.mutations)
			}
		}
		return nil
	}

	// MARK: - Types

	/// The type a node actually returns: a literal's own, a call's `->`
	/// type, or for an untyped node, vector if any of its untyped
	/// arguments is (as NodeSignature describes).
	func valueType(of expression: GeneratedExpression) -> NodeValueType {
		switch expression {
			case .scalar: return .scalar
			case .vector: return .vector
			case .call(let name, let arguments):
				let signature = generator.signatures[name]
				if let output = signature?.outputType { return output }
				let types = signature?.argumentTypes ?? []
				for (index, argument) in arguments.enumerated() where (index < types.count ? types[index] : nil) == nil {
					if valueType(of: argument) == .vector { return .vector }
				}
				return .scalar
		}
	}

	private static func fits(_ type: NodeValueType?, _ slot: NodeValueType?) -> Bool {
		slot == nil || type == nil || type == slot
	}

	/// Whether `expression` could be a whole genotype: a call with
	/// arguments that isn't one of the excluded roots, as the generator
	/// requires.
	private func canBeRoot(_ expression: GeneratedExpression) -> Bool {
		guard case .call(let name, let arguments) = expression, !arguments.isEmpty else { return false }
		return !generator.configuration.excludedRootFunctions.contains(name)
	}

	// MARK: - The walk

	private struct Walk {
		let mutator: ExpressionMutator
		let probability: Double
		let parentSubtrees: [GeneratedExpression]
		var mutations: [Mutation] = []

		/// `depth` follows the generator: 0 for the root call, 1 for its
		/// arguments. `slot` is the preferred type of the slot the node
		/// sits in (nil at the root).
		mutating func visit<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, depth: Int, path: [Int], using rng: inout G) -> GeneratedExpression {
			if Double.random(in: 0..<1, using: &rng) < probability,
			   let mutated = mutator.mutateNode(expression, slot: slot, depth: depth, parentSubtrees: parentSubtrees, using: &rng) {
				mutations.append(Mutation(kind: mutated.kind, path: path, before: expression, after: mutated.result))
				// New material isn't mutated again in the same child.
				return mutated.result
			}
			guard case .call(let name, let arguments) = expression, !arguments.isEmpty else { return expression }
			var types = mutator.generator.signatures[name]?.argumentTypes ?? []
			if types.count != arguments.count {
				types = Array(repeating: nil, count: arguments.count)
			}
			let children = arguments.indices.map { index in
				visit(arguments[index], slot: types[index], depth: depth + 1, path: path + [index], using: &rng)
			}
			return .call(name, children)
		}
	}

	// MARK: - One node

	/// Picks a kind by weight among those that apply to the node and
	/// applies it. A kind with nothing to pick from (no other function
	/// fits the slot, say) is dropped and another picked. nil if none
	/// applies.
	private func mutateNode<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, depth: Int, parentSubtrees: [GeneratedExpression], using rng: inout G) -> (kind: Kind, result: GeneratedExpression)? {
		var kinds: [(Kind, Double)]
		switch expression {
			case .scalar:
				let w = configuration.literalWeights
				kinds = [(.newExpression, w.newExpression), (.adjustScalar, w.adjust), (.wrap, w.wrap), (.copy, w.copy)]
			case .vector:
				let w = configuration.literalWeights
				kinds = [(.newExpression, w.newExpression), (.adjustVector, w.adjust), (.wrap, w.wrap), (.copy, w.copy)]
			case .call(_, let arguments) where arguments.isEmpty:
				let w = configuration.variableWeights
				kinds = [(.newExpression, w.newExpression), (.swapVariable, w.swap), (.wrap, w.wrap), (.copy, w.copy)]
			case .call:
				let w = configuration.callWeights
				kinds = [(.newExpression, w.newExpression), (.swapFunction, w.swap), (.wrap, w.wrap), (.hoist, w.hoist), (.copy, w.copy)]
		}
		kinds.removeAll { $0.1 <= 0 }

		let isRoot = depth == 0
		while let index = Self.weightedIndex(kinds.map(\.1), using: &rng) {
			let kind = kinds[index].0
			let result: GeneratedExpression?
			switch kind {
				case .newExpression: result = newExpression(slot: slot, depth: depth, using: &rng)
				case .adjustScalar: result = adjustScalar(expression, using: &rng)
				case .adjustVector: result = adjustVector(expression, using: &rng)
				case .swapFunction: result = swapFunction(expression, slot: slot, depth: depth, using: &rng)
				case .swapVariable: result = swapVariable(expression, slot: slot, using: &rng)
				case .wrap: result = wrap(expression, slot: slot, isRoot: isRoot, using: &rng)
				case .hoist: result = hoist(expression, slot: slot, isRoot: isRoot, using: &rng)
				case .copy: result = copy(expression, slot: slot, isRoot: isRoot, parentSubtrees: parentSubtrees, using: &rng)
			}
			// The root stays a call with arguments, as the generator makes
			// it, even for a parent like `x` (which can only wrap or be
			// replaced).
			if let result, !isRoot || result.isCallWithArguments {
				return (kind, result)
			}
			kinds.remove(at: index)
		}
		return nil
	}

	/// 1. Built exactly like first-generation material at this depth, so
	/// deep nodes mostly become terminals and `maxDepth` still holds.
	private func newExpression<G: RandomNumberGenerator>(slot: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression {
		depth == 0
			? generator.generate(using: &rng)
			: generator.randomArgument(preferring: slot, depth: depth, using: &rng)
	}

	/// 2.
	private func adjustScalar<G: RandomNumberGenerator>(_ expression: GeneratedExpression, using rng: inout G) -> GeneratedExpression? {
		guard case .scalar(let value) = expression else { return nil }
		let sigma = configuration.scalarSigma * max(abs(value), configuration.scalarSigmaFloor)
		return .scalar(Self.mutated(value + sigma * Self.gaussian(using: &rng)))
	}

	/// 3.
	private func adjustVector<G: RandomNumberGenerator>(_ expression: GeneratedExpression, using rng: inout G) -> GeneratedExpression? {
		guard case .vector(let r, let g, let b) = expression else { return nil }
		let sigma = configuration.vectorSigma
		return .vector(Self.mutated(r + sigma * Self.gaussian(using: &rng)),
					   Self.mutated(g + sigma * Self.gaussian(using: &rng)),
					   Self.mutated(b + sigma * Self.gaussian(using: &rng)))
	}

	/// 4. Any other function whose output fits the slot. Old arguments
	/// stay in their positions where they fit the new function's slot
	/// types; missing or misfitting ones are generated, extras dropped.
	private func swapFunction<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, depth: Int, using rng: inout G) -> GeneratedExpression? {
		guard case .call(let name, let arguments) = expression else { return nil }
		let pool = depth == 0 ? generator.rootFunctions : generator.functions
		guard let function = pool.filter({ $0.name != name && Self.fits($0.outputType, slot) }).randomElement(using: &rng) else {
			return nil
		}
		let newArguments = function.argumentTypes.enumerated().map { index, type in
			if index < arguments.count && Self.fits(valueType(of: arguments[index]), type) {
				return arguments[index]
			}
			return generator.randomArgument(preferring: type, depth: depth + 1, using: &rng)
		}
		return .call(function.name, newArguments)
	}

	/// 4, for a function with no arguments.
	private func swapVariable<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, using rng: inout G) -> GeneratedExpression? {
		guard case .call(let name, _) = expression else { return nil }
		return generator.variables
			.filter { $0.name != name && Self.fits($0.outputType, slot) }
			.randomElement(using: &rng)
			.map { .call($0.name, []) }
	}

	/// 5. A function that fits the slot and has a slot of its own this
	/// node fits; its other arguments are random terminals, like Sims'
	/// `X` to `(* X .3)`.
	private func wrap<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, isRoot: Bool, using rng: inout G) -> GeneratedExpression? {
		let type = valueType(of: expression)
		let pool = isRoot ? generator.rootFunctions : generator.functions
		let candidates = pool.filter { function in
			Self.fits(function.outputType, slot) && function.argumentTypes.contains { Self.fits(type, $0) }
		}
		guard let function = candidates.randomElement(using: &rng),
			  let position = function.argumentTypes.indices.filter({ Self.fits(type, function.argumentTypes[$0]) }).randomElement(using: &rng) else {
			return nil
		}
		let arguments = function.argumentTypes.enumerated().map { index, argumentType in
			index == position ? expression : generator.randomTerminal(preferring: argumentType, using: &rng)
		}
		return .call(function.name, arguments)
	}

	/// 6. One of the function's arguments that fits the slot.
	private func hoist<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, isRoot: Bool, using rng: inout G) -> GeneratedExpression? {
		guard case .call(_, let arguments) = expression else { return nil }
		return arguments
			.filter { Self.fits(valueType(of: $0), slot) && (!isRoot || canBeRoot($0)) }
			.randomElement(using: &rng)
	}

	/// 7. Any other node of the original parent (not the child being
	/// built) that fits the slot.
	private func copy<G: RandomNumberGenerator>(_ expression: GeneratedExpression, slot: NodeValueType?, isRoot: Bool, parentSubtrees: [GeneratedExpression], using rng: inout G) -> GeneratedExpression? {
		parentSubtrees
			.filter { $0 != expression && Self.fits(valueType(of: $0), slot) && (!isRoot || canBeRoot($0)) }
			.randomElement(using: &rng)
	}

	// MARK: - Helpers

	/// Three significant figures: one more than a new constant gets, so
	/// small adjustments to a value like 1.86 survive.
	private static func mutated(_ value: Double) -> Double {
		GeneratedExpression.rounded(value, significantFigures: 3)
	}

	/// Standard normal, by Box-Muller.
	static func gaussian<G: RandomNumberGenerator>(using rng: inout G) -> Double {
		let u1 = Double.random(in: Double.leastNormalMagnitude..<1, using: &rng)
		let u2 = Double.random(in: 0..<1, using: &rng)
		return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
	}

	private static func weightedIndex<G: RandomNumberGenerator>(_ weights: [Double], using rng: inout G) -> Int? {
		let total = weights.reduce(0, +)
		guard total > 0 else { return nil }
		var pick = Double.random(in: 0..<total, using: &rng)
		for (index, weight) in weights.enumerated() {
			if pick < weight { return index }
			pick -= weight
		}
		return weights.indices.last
	}
}

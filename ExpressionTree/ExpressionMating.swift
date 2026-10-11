//
//  ExpressionMating.swift
//  ExpressionTree
//
//  Sexual reproduction: a child from two parent genotypes, by Sims' two
//  methods (1991 §4.3; 1993 §2.2 keeps only the second). See the Mating
//  section of Documentation/EvolutionUI.md.
//
//  - Graft: a random node of one parent replaced by a random node of the
//    other. Which parent receives it is a coin flip per child (Andy,
//    2026-10-11).
//  - Crossover: both trees walked together; wherever they differ, either
//    parent's version is copied with equal chance. Only similar parents
//    make anything new.
//
//  Mated children aren't mutated as well (for now). They use the
//  mutator's typing (a slot gets a node that fits it, the root stays a
//  call) and size cap.
//

import Foundation

public enum MatingMethod: String, Sendable, CaseIterable {
	case graft
	case crossover
}

extension ExpressionMutator {
	public struct MatedChild: Sendable {
		public let expression: GeneratedExpression
		/// Which parent (0 or 1) the child is built on: the one that received
		/// the graft, or the first parent for a crossover.
		public let base: Int
		/// What came from the other parent: the path in the base, the base's
		/// node there and what replaced it.
		public let grafts: [Mutation]
	}

	/// Up to `count` different children of `parents`, none equal to either
	/// parent, drawn until `count` are found or about 50 draws per child
	/// go by without one. Crossover often can't make `count`: two parents
	/// with three differences make at most six new children.
	public func mate<G: RandomNumberGenerator>(_ parents: (GeneratedExpression, GeneratedExpression), method: MatingMethod,
											   count: Int, using rng: inout G) -> [MatedChild] {
		let limit = max(maxNodes(forParent: parents.0), maxNodes(forParent: parents.1))
		var children: [MatedChild] = []
		var seen: Set<GeneratedExpression> = [parents.0, parents.1]
		var misses = 0
		while children.count < count && misses < 50 * max(count, 1) {
			let drawn: MatedChild?
			switch method {
				case .graft: drawn = graft(parents, using: &rng)
				case .crossover: drawn = crossover(parents, using: &rng)
			}
			if let drawn, drawn.expression.nodeCount <= limit, seen.insert(drawn.expression).inserted {
				children.append(drawn)
			} else {
				misses += 1
			}
		}
		return children
	}

	/// Whether crossover can make anything: Sims' "different species".
	public func canCrossOver(_ a: GeneratedExpression, _ b: GeneratedExpression) -> Bool {
		guard case .call(let nameA, let argumentsA) = a, case .call(let nameB, let argumentsB) = b else { return false }
		return nameA == nameB && argumentsA.count == argumentsB.count && a != b
	}

	/// One graft, or nil if the receiving node has nothing in the donor
	/// that fits it.
	func graft<G: RandomNumberGenerator>(_ parents: (GeneratedExpression, GeneratedExpression), using rng: inout G) -> MatedChild? {
		let base = Bool.random(using: &rng) ? 1 : 0
		let (receiver, donor) = base == 0 ? (parents.0, parents.1) : (parents.1, parents.0)
		guard let site = typedSubtrees(of: receiver).randomElement(using: &rng) else { return nil }
		let isRoot = site.path.isEmpty
		let candidates = donor.subtrees().map(\.expression).filter { node in
			node != site.expression && Self.fits(valueType(of: node), site.slot) && (!isRoot || canBeRoot(node))
		}
		guard let replacement = candidates.randomElement(using: &rng) else { return nil }
		return MatedChild(expression: receiver.replacing(at: site.path, with: replacement), base: base,
						  grafts: [Mutation(kind: .graft, path: site.path, before: site.expression, after: replacement)])
	}

	/// One crossover child of the first parent: at each difference, a coin
	/// flip for whose version to copy.
	func crossover<G: RandomNumberGenerator>(_ parents: (GeneratedExpression, GeneratedExpression), using rng: inout G) -> MatedChild? {
		guard canCrossOver(parents.0, parents.1) else { return nil }
		var grafts: [Mutation] = []
		func walk(_ a: GeneratedExpression, _ b: GeneratedExpression, path: [Int]) -> GeneratedExpression {
			if a == b { return a }
			if case .call(let nameA, let argumentsA) = a, case .call(let nameB, let argumentsB) = b,
			   nameA == nameB, argumentsA.count == argumentsB.count {
				return .call(nameA, argumentsA.indices.map { walk(argumentsA[$0], argumentsB[$0], path: path + [$0]) })
			}
			if Bool.random(using: &rng) {
				grafts.append(Mutation(kind: .crossover, path: path, before: a, after: b))
				return b
			}
			return a
		}
		let child = walk(parents.0, parents.1, path: [])
		return MatedChild(expression: child, base: 0, grafts: grafts)
	}

	/// Every node with the preferred type of the slot it sits in (nil at
	/// the root and in untyped slots).
	func typedSubtrees(of expression: GeneratedExpression, slot: NodeValueType? = nil, path: [Int] = [])
		-> [(path: [Int], expression: GeneratedExpression, slot: NodeValueType?)] {
		var result = [(path, expression, slot)]
		if case .call(let name, let arguments) = expression {
			var types = generator.signatures[name]?.argumentTypes ?? []
			if types.count != arguments.count {
				types = Array(repeating: nil, count: arguments.count)
			}
			for index in arguments.indices {
				result += typedSubtrees(of: arguments[index], slot: types[index], path: path + [index])
			}
		}
		return result
	}
}

extension GeneratedExpression {
	/// This expression with the node at `path` (argument indices from the
	/// root) replaced.
	func replacing(at path: [Int], with replacement: GeneratedExpression) -> GeneratedExpression {
		guard let first = path.first else { return replacement }
		guard case .call(let name, var arguments) = self, arguments.indices.contains(first) else { return self }
		arguments[first] = arguments[first].replacing(at: Array(path.dropFirst()), with: replacement)
		return .call(name, arguments)
	}
}

//
//  ExpressionMutatorTests.swift
//  ExpressionTreeTests
//
//  Reading genotype text into a GeneratedExpression, and Sims' mutation
//  scheme in ExpressionMutator.
//

import Testing
import Foundation
@testable import ExpressionTree

private let repositoryRoot = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()

private let bundled = DSLLibrary.scanWithSignatures(
	roots: [repositoryRoot.appendingPathComponent("Evolv.io/Resources/BundledNodes")], reservedNames: [])

private let bundledGenotypes = GenotypeLibrary.scan(roots: [
	(repositoryRoot.appendingPathComponent("Evolv.io/Resources/BundledGenotypes"), .bundled),
]).genotypes

private func build(_ expression: GeneratedExpression) throws -> any Node {
	switch expression {
		case .scalar(let value): return Constant(value)
		case .vector(let r, let g, let b): return ConstantTriplet(Value(r, g, b))
		case .call(let name, let arguments): return try bundled.constructors[name]!(arguments.map(build))
	}
}

struct GeneratedExpressionParsingTests {
	@Test func readsEveryForm() throws {
		let expression = try GeneratedExpression(parsing: "(COLOR-GRAD (bw-noise .15 X) 3.1 -0.04 #(0.95 .7 0.59) 1.35)")
		#expect(expression == .call("color-grad", [
			.call("bw-noise", [.scalar(0.15), .call("x", [])]),
			.scalar(3.1), .scalar(-0.04), .vector(0.95, 0.7, 0.59), .scalar(1.35),
		]))
		#expect(try GeneratedExpression(parsing: "x") == .call("x", []))
		#expect(try GeneratedExpression(parsing: " 15.5 ") == .scalar(15.5))
	}

	@Test func rejectsBadText() {
		for text in ["", "(abs x", "(abs x))", "#(1 2)", "(1 2)", ")", "(abs #(1 2 x))"] {
			#expect(throws: GeneratedExpression.TextError.self, "\(text)") { try GeneratedExpression(parsing: text) }
		}
	}

	/// Every bundled genotype prints back to text that reads as the same
	/// tree, so mutating a parent never changes the parts left alone.
	@Test func bundledGenotypesRoundTrip() throws {
		#expect(bundledGenotypes.count >= 15)
		for genotype in bundledGenotypes {
			let expression = try GeneratedExpression(parsing: genotype.expression)
			#expect(try GeneratedExpression(parsing: expression.description) == expression, "\(genotype.id)")
		}
	}

	@Test func countsNodes() throws {
		#expect(try GeneratedExpression(parsing: "(+ (abs x) (* y #(0.6 0.6 0.6)))").nodeCount == 6)
		#expect(GeneratedExpression.scalar(1).nodeCount == 1)
	}
}

struct ExpressionMutatorTests {
	private let generator = RandomExpressionGenerator(signatures: bundled.signatures)

	private func mutator(_ change: (inout ExpressionMutator.Configuration) -> Void = { _ in }) -> ExpressionMutator {
		var configuration = ExpressionMutator.Configuration()
		change(&configuration)
		return ExpressionMutator(generator: generator, configuration: configuration)
	}

	private var parents: [GeneratedExpression] {
		bundledGenotypes.compactMap { try? GeneratedExpression(parsing: $0.expression) }
	}

	/// Only one kind of mutation allowed, everywhere it applies.
	private func only(_ kind: ExpressionMutator.Kind) -> ExpressionMutator {
		mutator { configuration in
			var weights = ExpressionMutator.Weights()
			switch kind {
				case .newExpression: weights.newExpression = 1
				case .adjustScalar, .adjustVector: weights.adjust = 1
				case .swapFunction, .swapVariable: weights.swap = 1
				case .wrap: weights.wrap = 1
				case .hoist: weights.hoist = 1
				case .copy: weights.copy = 1
			}
			configuration.callWeights = weights
			configuration.variableWeights = weights
			configuration.literalWeights = weights
		}
	}

	@Test func sameSeedSameChildren() throws {
		let parent = try GeneratedExpression(parsing: "(color-grad (bw-noise 0.15 x) 3.1 -0.04 #(0.95 0.7 0.59) 1.35)")
		func children(_ seed: UInt64) -> [GeneratedExpression] {
			var rng = SeededRandomNumberGenerator(seed: seed)
			return (0..<19).map { _ in mutator().mutate(parent, using: &rng)!.expression }
		}
		#expect(children(7) == children(7))
		#expect(children(7) != children(8))
	}

	@Test func childrenDifferFromTheParentAndBuild() throws {
		let mutator = mutator()
		var rng = SeededRandomNumberGenerator(seed: 1)
		for parent in parents {
			for _ in 0..<50 {
				let child = try #require(mutator.mutate(parent, using: &rng))
				#expect(child.expression != parent)
				#expect(!child.mutations.isEmpty)
				#expect(child.expression.nodeCount <= mutator.maxNodes(forParent: parent))
				_ = try build(child.expression)
			}
		}
	}

	/// The log's paths point at what changed: applying each logged
	/// mutation to the parent, in order, rebuilds the child.
	@Test func mutationLogRebuildsTheChild() throws {
		func replacing(_ expression: GeneratedExpression, at path: ArraySlice<Int>, with replacement: GeneratedExpression) -> GeneratedExpression {
			guard let index = path.first, case .call(let name, var arguments) = expression else { return replacement }
			arguments[index] = replacing(arguments[index], at: path.dropFirst(), with: replacement)
			return .call(name, arguments)
		}
		let mutator = mutator { $0.mutationsPerChild = 3 }
		var rng = SeededRandomNumberGenerator(seed: 2)
		for parent in parents {
			for _ in 0..<20 {
				let child = try #require(mutator.mutate(parent, using: &rng))
				var rebuilt = parent
				for mutation in child.mutations {
					rebuilt = replacing(rebuilt, at: mutation.path[...], with: mutation.after)
				}
				#expect(rebuilt == child.expression)
			}
		}
	}

	@Test func adjustScalarStaysNearAndRounds() throws {
		let parent = try GeneratedExpression(parsing: "(bw-noise 15.5 0.2)")
		var rng = SeededRandomNumberGenerator(seed: 3)
		var moves: [Double] = []
		for _ in 0..<500 {
			let child = try #require(only(.adjustScalar).mutate(parent, using: &rng))
			for mutation in child.mutations {
				#expect(mutation.kind == .adjustScalar)
				guard case .scalar(let before) = mutation.before, case .scalar(let after) = mutation.after else {
					Issue.record("not a scalar: \(mutation)")
					continue
				}
				#expect(after == GeneratedExpression.rounded(after, significantFigures: 3))
				if before == 15.5 { moves.append(abs(after - before)) }
			}
		}
		// Proportional: 15.5 has a standard deviation of about 3.9.
		let mean = moves.reduce(0, +) / Double(moves.count)
		#expect((2.0...4.5).contains(mean), "mean move \(mean)")
	}

	@Test func adjustVectorChangesEveryElement() throws {
		let parent = try GeneratedExpression(parsing: "(hsv-to-rgb #(0.5 0.5 0.5))")
		var rng = SeededRandomNumberGenerator(seed: 4)
		let child = try #require(only(.adjustVector).mutate(parent, using: &rng))
		guard case .call(_, let arguments) = child.expression, case .vector(let r, let g, let b) = arguments[0] else {
			Issue.record("unexpected child \(child.expression)")
			return
		}
		#expect(r != 0.5 && g != 0.5 && b != 0.5)
	}

	/// Sims: `(abs X)` might become `(cos X)`.
	@Test func swapFunctionKeepsFittingArguments() throws {
		let parent = try GeneratedExpression(parsing: "(abs x)")
		var rng = SeededRandomNumberGenerator(seed: 5)
		var swaps = 0
		var keptX = 0
		for _ in 0..<300 {
			let child = try #require(only(.swapFunction).mutate(parent, using: &rng))
			guard child.mutations.first?.kind == .swapFunction,
				  case .call(let name, let arguments) = child.expression else { continue }
			swaps += 1
			#expect(name != "abs")
			#expect(arguments.count == bundled.signatures[name]!.arity)
			if arguments.first == .call("x", []) { keptX += 1 }
		}
		// Most functions' first slot takes a scalar, so x stays there.
		#expect(swaps > 100)
		#expect(Double(keptX) > 0.7 * Double(swaps))
	}

	@Test func swapVariable() throws {
		let parent = try GeneratedExpression(parsing: "(abs x)")
		var rng = SeededRandomNumberGenerator(seed: 6)
		var swaps = 0
		for _ in 0..<100 {
			let child = try #require(only(.swapVariable).mutate(parent, using: &rng))
			for mutation in child.mutations where mutation.kind == .swapVariable {
				swaps += 1
				#expect(mutation.path == [0])
				#expect(mutation.after == .call("y", []))
			}
		}
		#expect(swaps > 10)
	}

	/// Sims: `X` might become `(* X .3)`.
	@Test func wrapPutsTheNodeInsideANewFunction() throws {
		let parent = try GeneratedExpression(parsing: "(abs x)")
		var rng = SeededRandomNumberGenerator(seed: 7)
		for _ in 0..<100 {
			let child = try #require(only(.wrap).mutate(parent, using: &rng))
			let mutation = try #require(child.mutations.first)
			guard case .call(_, let arguments) = mutation.after else {
				Issue.record("wrap gave a terminal")
				continue
			}
			#expect(arguments.contains(mutation.before))
		}
	}

	/// Sims: `(* X .3)` might become `X`.
	@Test func hoistReplacesAFunctionWithAnArgument() throws {
		let parent = try GeneratedExpression(parsing: "(abs (* x 0.3))")
		var rng = SeededRandomNumberGenerator(seed: 8)
		var seen: Set<String> = []
		for _ in 0..<100 {
			let child = try #require(only(.hoist).mutate(parent, using: &rng))
			seen.insert(child.expression.description)
		}
		// The root hoists to (* x 0.3); a variable or literal never
		// becomes the root.
		#expect(seen.isSubset(of: ["(abs x)", "(abs 0.3)", "(* x 0.3)"]))
		#expect(seen.contains("(abs x)"))
	}

	/// Sims: `(+ (abs X) (* Y .6))` might become `(+ (abs (* Y .6)) (* Y .6))`.
	@Test func copyUsesNodesOfTheParent() throws {
		let parent = try GeneratedExpression(parsing: "(+ (abs x) (* y 0.6))")
		let parentNodes = Set(parent.subtrees().map(\.expression))
		var rng = SeededRandomNumberGenerator(seed: 9)
		var children: Set<String> = []
		for _ in 0..<300 {
			let child = try #require(only(.copy).mutate(parent, using: &rng))
			for mutation in child.mutations {
				#expect(parentNodes.contains(mutation.after))
			}
			children.insert(child.expression.description)
		}
		#expect(children.contains("(+ (abs (* y 0.6)) (* y 0.6))"))
	}

	@Test func newExpressionIsLikeFirstGeneration() throws {
		let parent = try GeneratedExpression(parsing: "(abs x)")
		var rng = SeededRandomNumberGenerator(seed: 10)
		for _ in 0..<100 {
			let child = try #require(only(.newExpression).mutate(parent, using: &rng))
			_ = try build(child.expression)
		}
	}

	@Test func replacementsFitTypedSlots() throws {
		// color-grad's p1, p2, p3 are scalar slots and its colour a vector one.
		let parent = try GeneratedExpression(parsing: "(color-grad (bw-noise 0.15 2) 3.1 -0.04 #(0.95 0.7 0.59) 1.35)")
		let mutator = mutator { $0.mutationsPerChild = 4 }
		var rng = SeededRandomNumberGenerator(seed: 11)
		for _ in 0..<500 {
			let child = try #require(mutator.mutate(parent, using: &rng))
			for mutation in child.mutations where mutation.path.count == 1 {
				guard let slot = bundled.signatures["color-grad"]!.argumentTypes[mutation.path[0]] else { continue }
				// Like the generator: literals and typed nodes match the
				// slot; untyped nodes may go anywhere.
				let declared: NodeValueType?
				switch mutation.after {
					case .scalar: declared = .scalar
					case .vector: declared = .vector
					case .call(let name, _): declared = bundled.signatures[name]!.outputType
				}
				#expect(declared == nil || declared == slot, "\(mutation.after) in a \(slot) slot")
			}
		}
	}

	@Test func rootStaysAFunction() throws {
		let mutator = mutator { $0.mutationsPerChild = 3 }
		var rng = SeededRandomNumberGenerator(seed: 12)
		for parent in parents {
			for _ in 0..<50 {
				let child = try #require(mutator.mutate(parent, using: &rng))
				guard case .call(let name, let arguments) = child.expression, !arguments.isEmpty else {
					Issue.record("root isn't a call: \(child.expression)")
					continue
				}
				// A parent whose root is already excluded may keep it.
				if case .call(let parentRoot, _) = parent, parentRoot == name { continue }
				#expect(!generator.configuration.excludedRootFunctions.contains(name))
			}
		}
	}

	@Test func unknownNodes() throws {
		#expect(mutator().unknownNodes(in: try GeneratedExpression(parsing: "(abs (frob x 1))")) == ["frob"])
		for parent in parents {
			#expect(mutator().unknownNodes(in: parent).isEmpty)
		}
	}

	/// Andy wants trees to drift very slightly bigger (Mutation.md): over
	/// many children of random genotypes of 40+ nodes, the mean change is
	/// small and positive, and bigger than when new material is sized at
	/// its real depth (the Sims-style setting).
	@Test func sizeDriftIsSlightlyUpward() throws {
		var founderRNG = SeededRandomNumberGenerator(seed: 99)
		var founders: [GeneratedExpression] = []
		while founders.count < 150 {
			let founder = generator.generate(using: &founderRNG)
			if founder.nodeCount >= 40 { founders.append(founder) }
		}
		func meanChange(_ mutator: ExpressionMutator) throws -> Double {
			var rng = SeededRandomNumberGenerator(seed: 13)
			var total = 0
			for parent in founders {
				for _ in 0..<20 {
					total += try #require(mutator.mutate(parent, using: &rng)).expression.nodeCount - parent.nodeCount
				}
			}
			return Double(total) / Double(founders.count * 20)
		}
		let drift = try meanChange(mutator())
		let realDepth = try meanChange(mutator { $0.newMaterialChanceDepth = nil })
		#expect(drift > 0)
		#expect(drift < 4)
		#expect(drift > realDepth)
	}

	@Test func sizeCap() throws {
		let mutator = mutator()
		let small = try GeneratedExpression(parsing: "(abs x)")
		#expect(mutator.maxNodes(forParent: small) == 200)
		// Wide rather than deep, since only the count matters here.
		func tree(_ nodeCount: Int) -> GeneratedExpression {
			.call("f", Array(repeating: .call("x", []), count: nodeCount - 1))
		}
		#expect(mutator.maxNodes(forParent: tree(150)) == 300)
		#expect(mutator.maxNodes(forParent: tree(700)) == 1000)
		#expect(mutator.maxNodes(forParent: tree(1200)) == 1200)
	}
}

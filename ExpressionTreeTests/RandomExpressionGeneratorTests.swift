//
//  RandomExpressionGeneratorTests.swift
//  ExpressionTreeTests
//
//  The `.evolvnode` type annotations (`p1: scalar`, `-> vector`) and the
//  random expression generator that uses them.
//

import Testing
import Foundation
@testable import ExpressionTree

private let bundledNodesDirectory = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("Evolv.io/Resources/BundledNodes")

private let bundled = DSLLibrary.scanWithSignatures(roots: [bundledNodesDirectory], reservedNames: [])

struct NodeTypeAnnotationTests {
	@Test func parsesParamTypesAndOutputType() throws {
		let source = """
		node "t"(a, b: scalar, c: vector, d: fn, e: fn scalar, f: vector fn) -> vector {
			return a
		}
		"""
		let template = try DSLParser(source).parseTemplate()
		#expect(template.params.map(\.preferredType) == [nil, .scalar, .vector, nil, .scalar, .vector])
		#expect(template.params.map(\.isFunction) == [false, false, false, true, true, true])
		#expect(template.outputType == .vector)
	}

	@Test func outputTypeIsOptional() throws {
		let template = try DSLParser(#"node "t"(a) requires(perlin) { return a }"#).parseTemplate()
		#expect(template.outputType == nil)
		#expect(template.requires == ["perlin"])
	}

	@Test func rejectsUnknownTypes() {
		#expect(throws: DSLParseError.self) { try DSLParser(#"node "t"(a: colour) { return a }"#).parseTemplate() }
		#expect(throws: DSLParseError.self) { try DSLParser(#"node "t"(a) -> colour { return a }"#).parseTemplate() }
		#expect(throws: DSLParseError.self) { try DSLParser(#"node "t"(a: scalar vector) { return a }"#).parseTemplate() }
		#expect(throws: DSLParseError.self) { try DSLParser(#"node "t"(a: fn value) { return a }"#).parseTemplate() }
	}

	@Test func parsesNonconst() throws {
		let template = try DSLParser(#"node "rng"() -> scalar nonconst requires(perlin) { return float3(0.5) }"#).parseTemplate()
		#expect(template.isNonconst)
		#expect(template.outputType == .scalar)
		#expect(template.requires == ["perlin"])
		#expect(try DSLParser(#"node "x"() -> scalar { return float3(0.5) }"#).parseTemplate().isNonconst == false)
		// Only a node with no params could be a terminal in the first place.
		#expect(throws: DSLParseError.self) { try DSLParser(#"node "t"(a) nonconst { return a }"#).parseTemplate() }
	}

	@Test func bundledSignatures() throws {
		#expect(bundled.issues.isEmpty)
		let colorGrad = try #require(bundled.signatures["color-grad"])
		#expect(colorGrad.argumentTypes == [nil, .scalar, .scalar, .vector, .scalar])
		#expect(colorGrad.outputType == .vector)
		#expect(bundled.signatures["bw-noise"]?.outputType == .scalar)
		#expect(bundled.signatures["x"]?.arity == 0)
		#expect(bundled.signatures["+"]?.argumentTypes == [nil, nil])
		#expect(bundled.signatures["+"]?.outputType == nil)
		#expect(Set(bundled.signatures.keys) == Set(bundled.constructors.keys))
	}
}

struct RandomExpressionGeneratorTests {
	private let generator = RandomExpressionGenerator(signatures: bundled.signatures)

	private func sample(count: Int = 500, seed: UInt64 = 1) -> [GeneratedExpression] {
		var rng = SeededRandomNumberGenerator(seed: seed)
		return (0..<count).map { _ in generator.generate(using: &rng) }
	}

	@Test func sameSeedSameExpressions() {
		#expect(sample(count: 20, seed: 42) == sample(count: 20, seed: 42))
		#expect(sample(count: 20, seed: 42) != sample(count: 20, seed: 43))
	}

	@Test func rootIsAlwaysAFunction() {
		for expression in sample() {
			guard case .call(let name, let arguments) = expression else {
				Issue.record("root is a literal: \(expression)")
				continue
			}
			#expect(!arguments.isEmpty, "root is a variable: \(name)")
		}
	}

	@Test func excludedRootNodesOnlyMissTheRoot() {
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.excludedRootFunctions = ["vector", "+"]
		let generator = RandomExpressionGenerator(signatures: bundled.signatures, configuration: configuration)
		var rng = SeededRandomNumberGenerator(seed: 1)
		var belowRoot: Set<String> = []
		func collect(_ expression: GeneratedExpression) {
			guard case .call(let name, let arguments) = expression else { return }
			belowRoot.insert(name)
			arguments.forEach(collect)
		}
		for _ in 0..<500 {
			guard case .call(let root, let arguments) = generator.generate(using: &rng) else { continue }
			#expect(!configuration.excludedRootFunctions.contains(root), "excluded node at the root: \(root)")
			arguments.forEach(collect)
		}
		#expect(belowRoot.isSuperset(of: ["vector", "+"]))
	}

	@Test func defaultExcludedRootNodes() {
		#expect(RandomExpressionGenerator.Configuration().excludedRootFunctions == ["constant", "triplet-constant", "vector"])
	}

	@Test func argumentsFollowPreferredTypes() {
		func check(_ expression: GeneratedExpression) {
			guard case .call(let name, let arguments) = expression, !arguments.isEmpty else { return }
			let signature = bundled.signatures[name]!
			#expect(arguments.count == signature.arity)
			for (argument, type) in zip(arguments, signature.argumentTypes) {
				switch (argument, type) {
					case (.vector, .scalar):
						Issue.record("vector literal in a scalar slot of \(name): \(expression)")
					case (.scalar, .vector):
						Issue.record("scalar literal in a vector slot of \(name): \(expression)")
					case (.call(let inner, _), .some(let type)):
						// Functions and variables both fit by output type.
						let output = bundled.signatures[inner]!.outputType
						#expect(output == nil || output == type, "\(inner) in a \(type) slot of \(name): \(expression)")
					default:
						break
				}
				check(argument)
			}
		}
		sample().forEach(check)
	}

	@Test(arguments: [2, 4])
	func depthIsCapped(maxDepth: Int) {
		func depth(_ expression: GeneratedExpression) -> Int {
			guard case .call(_, let arguments) = expression, !arguments.isEmpty else { return 0 }
			return 1 + (arguments.map(depth).max() ?? 0)
		}
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.maxDepth = maxDepth
		let generator = RandomExpressionGenerator(signatures: bundled.signatures, configuration: configuration)
		var rng = SeededRandomNumberGenerator(seed: 1)
		// maxDepth counts levels of calls, the root included; the deepest
		// calls' arguments are leaves.
		let depths = (0..<500).map { _ in depth(generator.generate(using: &rng)) }
		#expect(depths.max()! <= maxDepth)
		#expect(depths.contains(maxDepth))
	}

	@Test func variablesAreXAndY() {
		var variables: Set<String> = []
		func collect(_ expression: GeneratedExpression) {
			guard case .call(let name, let arguments) = expression else { return }
			if arguments.isEmpty { variables.insert(name) }
			arguments.forEach(collect)
		}
		sample().forEach(collect)
		#expect(variables == ["x", "y"])
	}

	@Test func everyNoArgumentNodeIsAVariable() {
		var signatures = bundled.signatures
		signatures["r"] = NodeSignature(name: "r", argumentTypes: [], outputType: .scalar)
		signatures["sky"] = NodeSignature(name: "sky", argumentTypes: [], outputType: .vector)
		let generator = RandomExpressionGenerator(signatures: signatures)
		var rng = SeededRandomNumberGenerator(seed: 1)
		var variables: Set<String> = []
		func collect(_ expression: GeneratedExpression) {
			guard case .call(let name, let arguments) = expression else { return }
			if arguments.isEmpty { variables.insert(name) }
			arguments.forEach(collect)
		}
		for _ in 0..<500 {
			let expression = generator.generate(using: &rng)
			guard case .call(let root, _) = expression else { continue }
			#expect(!["r", "sky"].contains(root), "a variable at the root: \(root)")
			collect(expression)
		}
		// `z` is excluded by default; user nodes are picked up automatically.
		#expect(variables == ["x", "y", "r", "sky"])
	}

	@Test func everyExpressionBuildsANodeTree() throws {
		func build(_ expression: GeneratedExpression) throws -> any Node {
			switch expression {
				case .scalar(let value): return Constant(value)
				case .vector(let r, let g, let b): return ConstantTriplet(Value(r, g, b))
				case .call(let name, let arguments): return try bundled.constructors[name]!(arguments.map(build))
			}
		}
		for expression in sample() {
			_ = try build(expression)
		}
	}

	@Test func expressionProbabilityFallsWithDepth() {
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.expressionProbability = 0.8
		configuration.expressionProbabilityDecay = 0.5
		let generator = RandomExpressionGenerator(signatures: bundled.signatures, configuration: configuration)
		#expect(generator.expressionProbability(atDepth: 1) == 0.8)
		#expect(generator.expressionProbability(atDepth: 2) == 0.4)
		#expect(generator.expressionProbability(atDepth: 3) == 0.2)
	}

	@Test func nonconstNodesAreFunctions() {
		var signatures = bundled.signatures
		signatures["rng"] = NodeSignature(name: "rng", argumentTypes: [], outputType: .scalar, isNonconst: true)
		var configuration = RandomExpressionGenerator.Configuration()
		// Every argument is a terminal, so a function only shows up at the root.
		configuration.expressionProbability = 0
		let generator = RandomExpressionGenerator(signatures: signatures, configuration: configuration)
		var rng = SeededRandomNumberGenerator(seed: 1)
		var roots: Set<String> = []
		for _ in 0..<2000 {
			guard case .call(let root, let arguments) = generator.generate(using: &rng) else { continue }
			roots.insert(root)
			for case .call(let name, _) in arguments {
				#expect(name != "rng", "nonconst node used as a variable")
			}
		}
		#expect(roots.contains("rng"))
		#expect(roots.isDisjoint(with: ["x", "y"]))
	}

	@Test func terminalWeightsPickTheTerminal() {
		var configuration = RandomExpressionGenerator.Configuration()
		configuration.terminalWeights = .init(scalar: 0, vector: 0, variable: 1)
		let generator = RandomExpressionGenerator(signatures: bundled.signatures, configuration: configuration)
		var rng = SeededRandomNumberGenerator(seed: 1)
		// With constants weighted to zero, only vector slots get literals.
		func check(_ expression: GeneratedExpression) {
			guard case .call(let name, let arguments) = expression, !arguments.isEmpty else { return }
			for (argument, type) in zip(arguments, bundled.signatures[name]!.argumentTypes) {
				switch argument {
					case .scalar: Issue.record("scalar literal in \(name): \(expression)")
					case .vector: #expect(type == .vector, "vector literal in a non-vector slot of \(name)")
					case .call: check(argument)
				}
			}
		}
		for _ in 0..<500 { check(generator.generate(using: &rng)) }
	}

	@Test func descriptionIsGenotypeText() {
		let expression = GeneratedExpression.call("color-grad", [
			.call("bw-noise", [.scalar(0.15), .call("x", [])]),
			.scalar(3.1), .scalar(-0.04), .vector(0.95, 0.7, 0.59), .scalar(1.35),
		])
		#expect(expression.description == "(color-grad (bw-noise 0.15 x) 3.1 -0.04 #(0.95 0.7 0.59) 1.4)")
	}
}

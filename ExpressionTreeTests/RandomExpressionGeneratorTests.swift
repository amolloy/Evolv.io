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
					case (.call(let inner, let innerArguments), .some(let type)):
						let output = bundled.signatures[inner]!.outputType
						if innerArguments.isEmpty {
							#expect(type == .scalar, "variable in a vector slot of \(name): \(expression)")
						} else {
							#expect(output == nil || output == type, "\(inner) in a \(type) slot of \(name): \(expression)")
						}
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

	@Test func descriptionIsGenotypeText() {
		let expression = GeneratedExpression.call("color-grad", [
			.call("bw-noise", [.scalar(0.15), .call("x", [])]),
			.scalar(3.1), .scalar(-0.04), .vector(0.95, 0.7, 0.59), .scalar(1.35),
		])
		#expect(expression.description == "(color-grad (bw-noise 0.15 x) 3.1 -0.04 #(0.95 0.7 0.59) 1.4)")
	}
}

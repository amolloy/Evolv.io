//
//  DSLLoopTests.swift
//  ExpressionTreeTests
//
//  The DSL's runtime `loop` (with `var`, assignment and `break if`), and
//  the bundled nodes built on it: ifs, warped-ifs and kaleidoscope.
//

import Testing
import Foundation
@testable import ExpressionTree

private let bundledNodesDirectory = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appendingPathComponent("Evolv.io/Resources/BundledNodes")

/// Compiles `source` (one node file) and evaluates it at `coord`.
private func evaluate(_ source: String, children: [any Node] = [], at coord: Coordinate = Coordinate(0.3, -0.4)) throws -> Value {
	let node = try DSLCodegenNode(template: try DSLParser(source).parseTemplate(), children: children)
	return try MSLTreeEvaluator().evaluate(node: node, at: [coord])[0]
}

struct DSLLoopParserTests {
	@Test func parsesLoopVarAssignAndBreak() throws {
		let template = try DSLParser("""
		node "t"(n) {
			var s: float = 0.0
			loop(i in 0..<n.x, max: 8) {
				let k: float = float(i)
				s = s + k
				break if s > 3.0
			}
			return float3(s)
		}
		""").parseTemplate()
		#expect(template.body.count == 2)
		guard case .variable(let decl) = template.body[0] else {
			Issue.record("expected a var statement, got \(template.body[0])")
			return
		}
		#expect(decl.name == "s")
		guard case .loop(let loop) = template.body[1] else {
			Issue.record("expected a loop statement, got \(template.body[1])")
			return
		}
		#expect(loop.variable == "i")
		#expect(loop.body.count == 3)
		guard case .assign(let name, _) = loop.body[1], case .breakIf = loop.body[2] else {
			Issue.record("expected assign then break if, got \(loop.body)")
			return
		}
		#expect(name == "s")
	}

	@Test func loopsParseInModuleFunctions() throws {
		let file = try DSLParser("""
		module "m" {
			func f(n: float) -> float {
				var s: float = 0.0
				loop(i in 0..<n, max: 4) {
					s = s + 1.0
				}
				return s
			}
		}
		""").parseFile()
		guard case .module(let module) = file else {
			Issue.record("expected a module")
			return
		}
		#expect(module.funcs[0].body.count == 2)
	}

	@Test func rejectsBreakOutsideALoop() {
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"() { break if 1.0 > 0.0 return float3(0.0) }"#).parseTemplate()
		}
	}

	/// An `average` body is unrolled inline, so a `break` there would leave
	/// an enclosing loop halfway through an expression.
	@Test func rejectsBreakInsideAverageInsideALoop() {
		#expect(throws: DSLParseError.self) {
			try DSLParser("""
			node "t"() {
				var s: float = 0.0
				loop(i in 0..<4, max: 4) {
					s = s + average(j in 0...1) {
						break if s > 1.0
						1.0
					}
				}
				return float3(s)
			}
			""").parseTemplate()
		}
	}

	@Test func rejectsAssigningToALetOrAChildParam() {
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"() { let a: float = 1.0 a = 2.0 return float3(a) }"#).parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"(v) { v = float3(1.0) return v }"#).parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"() { undeclared = 1.0 return float3(0.0) }"#).parseTemplate()
		}
	}

	/// A `let` inside a loop body shadows an outer `var` of the same name
	/// for the rest of that body.
	@Test func rejectsAssigningToALetThatShadowsAVar() {
		#expect(throws: DSLParseError.self) {
			try DSLParser("""
			node "t"() {
				var s: float = 0.0
				loop(i in 0..<4, max: 4) {
					let s: float = 1.0
					s = 2.0
				}
				return float3(s)
			}
			""").parseTemplate()
		}
	}

	@Test func rejectsNonIntegerLoopBounds() {
		// max must be known at compile time.
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"(n) { loop(i in 0..<4, max: n.x) { } return n }"#).parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"(n) { loop(i in 0..<4, max: 2.5) { } return n }"#).parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			try DSLParser(#"node "t"(n) { loop(i in n.x..<4, max: 4) { } return n }"#).parseTemplate()
		}
	}
}

struct DSLLoopCodegenTests {
	@Test func carriesStateAcrossIterations() throws {
		let result = try evaluate("""
		node "t"() {
			var s: float = 0.0
			loop(i in 0..<5, max: 10) {
				s = s + float(i)
			}
			return float3(s)
		}
		""")
		#expect(result == Value(repeating: 10))
	}

	@Test func lowerBoundOffsetsTheCounter() throws {
		let result = try evaluate("""
		node "t"() {
			var s: float = 0.0
			loop(i in 2..<5, max: 10) {
				s = s + float(i)
			}
			return float3(s)
		}
		""")
		#expect(result == Value(repeating: 9))
	}

	/// `hi` is a runtime value (a child here), but `max` caps the count,
	/// so a mutated argument of 1e6 can't hang the GPU; a negative `hi`
	/// runs no iterations at all.
	@Test func runtimeUpperBoundIsClampedToMax() throws {
		let source = """
		node "t"(n) {
			var count: float = 0.0
			loop(i in 0..<n.x, max: 8) {
				count = count + 1.0
			}
			return float3(count)
		}
		"""
		#expect(try evaluate(source, children: [Constant(3)]) == Value(repeating: 3))
		#expect(try evaluate(source, children: [Constant(3.5)]) == Value(repeating: 4))
		#expect(try evaluate(source, children: [Constant(1e6)]) == Value(repeating: 8))
		#expect(try evaluate(source, children: [Constant(-5)]) == Value(repeating: 0))
	}

	@Test func breakIfExitsEarly() throws {
		let result = try evaluate("""
		node "t"() {
			var s: float = 1.0
			var steps: float = 0.0
			loop(i in 0..<64, max: 64) {
				s = s * 2.0
				steps = steps + 1.0
				break if s > 100.0
			}
			return float3(s, steps, 0.0)
		}
		""")
		#expect(result == Value(128, 7, 0))
	}

	@Test func nestedLoopsAndMaxFromAnIntParam() throws {
		let result = try evaluate("""
		node "t"() {
			param $n: int = 3
			var s: float = 0.0
			loop(i in 0..<10, max: $n) {
				loop(j in 0..<10, max: $n) {
					s = s + float(i * 10 + j)
				}
			}
			return float3(s)
		}
		""")
		// i, j in 0..<3: sum of 10i + j = 3 * (0+10+20) + 3 * (0+1+2)
		#expect(result == Value(repeating: 99))
	}

	/// A `let` in a loop body is a fresh local every iteration, and
	/// `var`s declared inside the body don't leak out of it.
	@Test func letsAndVarsAreScopedToTheLoopBody() throws {
		let result = try evaluate("""
		node "t"() {
			var s: float = 0.0
			loop(i in 0..<3, max: 3) {
				var inner: float = float(i)
				inner = inner * inner
				let squared: float = inner
				s = s + squared
			}
			let inner: float = 100.0
			return float3(s, inner, 0.0)
		}
		""")
		#expect(result == Value(5, 100, 0))
	}

	/// The example in EvolvNodeFormat.md's `loop` section.
	@Test func documentationExampleCompilesAndRuns() throws {
		let source = """
		node "julia"(n: scalar, cx: scalar, cy: scalar) -> scalar {
			let c: float2 = float2(cx.x, cy.x)
			var z: float2 = coord * 2.0
			var steps: float = 0.0
			loop(i in 0..<n.x, max: 32) {
				z = float2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c
				steps = steps + 1.0
				break if dot(z, z) > 4.0
			}
			return float3(steps / 32.0)
		}
		"""
		// z starts at 2 * (0.9, 0.9), outside radius 2: escapes on step 1.
		let outside = try evaluate(source, children: [Constant(32), Constant(-0.8), Constant(0.156)], at: Coordinate(0.9, 0.9))
		#expect(outside == Value(repeating: 1.0 / 32.0))
		// c = 0, z = 0 never escapes: all 32 steps.
		let inside = try evaluate(source, children: [Constant(1e6), Constant(0), Constant(0)], at: Coordinate(0, 0))
		#expect(inside == Value(repeating: 1))
	}

	@Test func loopsRunInsideModuleFunctions() throws {
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: tempDir) }
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		try """
		module "loops" {
			func triangle(n: float) -> float {
				var s: float = 0.0
				loop(i in 1..<n + 1.0, max: 16) {
					s = s + float(i)
				}
				return s
			}
		}
		""".write(to: tempDir.appendingPathComponent("loops.evolvnode"), atomically: true, encoding: .utf8)
		try """
		node "triangle"(n) requires(loops) {
			return float3(triangle(n.x))
		}
		""".write(to: tempDir.appendingPathComponent("triangle.evolvnode"), atomically: true, encoding: .utf8)

		let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
		#expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
		let constructor = try #require(constructors["triangle"])
		let node = try constructor([Constant(4)])
		let actual = try MSLTreeEvaluator().evaluate(node: node, at: [Coordinate(0, 0)])[0]
		#expect(actual == Value(repeating: 10))
	}
}

/// ifs, warped-ifs and kaleidoscope: first-draft interpretations, so these
/// check structure (sharing, symmetry, robustness), not golden images.
struct LoopNodeTests {
	private static let constructors: [String: NodeRegistry.NodeConstructor] = {
		let (constructors, issues) = DSLLibrary.scan(roots: [bundledNodesDirectory], reservedNames: [])
		precondition(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
		return constructors
	}()

	private static func make(_ name: String, _ children: [any Node]) throws -> any Node {
		let constructor = try #require(constructors[name])
		return try constructor(children)
	}

	/// 1993 Figure 6's ifs arguments.
	private static let figure6Args: [Double] = [4.5, 0.82, 0.22, 3.8, 0.45, 0.049, 3.7, 16.1, -0.87, 2.3, 0.10, 0.46, -5.0, 7.6, 12.6, 0.05]
	private static let coords = [Coordinate(0.3, -0.4), Coordinate(-0.7, 0.1), Coordinate(0.02, 0.05), Coordinate(0.9, 0.9)]

	private static func assertFiniteInUnitRange(_ values: [Value]) {
		for v in values {
			for c in 0..<3 {
				#expect(v[c].isFinite && v[c] >= 0 && v[c] <= 1, "out of range: \(v)")
			}
		}
	}

	@Test func ifsIsFiniteAndInRange() throws {
		let node = try Self.make("ifs", Self.figure6Args.map { Constant($0) })
		let values = try MSLTreeEvaluator().evaluate(node: node, at: Self.coords)
		Self.assertFiniteInUnitRange(values)
		// Not a constant image.
		#expect(Set(values.map(\.x)).count > 1)
	}

	/// Mutation can hand any argument a wild value; every one must still
	/// give a finite result.
	@Test func ifsSurvivesWildArguments() throws {
		let wild: [Double] = [1e6, -1e6, 31, -31, 1e9, -1e9, 0, 0, 0, 0, 1e20, -1e20, 1e20, -1e20, 1e7, 1e7]
		let node = try Self.make("ifs", wild.map { Constant($0) })
		Self.assertFiniteInUnitRange(try MSLTreeEvaluator().evaluate(node: node, at: Self.coords))
	}

	/// warped-ifs shares ifs's module, so warped-ifs with (u, v) = (x, y)
	/// must match ifs exactly.
	@Test func warpedIfsOfXYMatchesIfs() throws {
		let args = Self.figure6Args.map { Constant($0) as any Node }
		let ifs = try Self.make("ifs", args)
		let warped = try Self.make("warped-ifs", [try Self.make("x", []), try Self.make("y", [])] + args)
		let evaluator = try MSLTreeEvaluator()
		let expected = try evaluator.evaluate(node: ifs, at: Self.coords)
		let actual = try evaluator.evaluate(node: warped, at: Self.coords)
		for (e, a) in zip(expected, actual) {
			#expect(Swift.abs(e.x - a.x) < 1e-5 && Swift.abs(e.x - a.y) < 1e-5 && Swift.abs(e.x - a.z) < 1e-5, "ifs \(e) vs warped-ifs \(a)")
		}
	}

	/// With no twist or offset, kaleidoscope's value at a point and at its
	/// mirror image across the top mirror (the line y = h) must agree.
	@Test func kaleidoscopeIsSymmetricAcrossAMirror() throws {
		let size = 2.1
		let side = 1 / (0.25 + size)
		let h = side / (2 * 3.0.squareRoot())
		let node = try Self.make("kaleidoscope", [Constant(size), Constant(0), try Self.make("x", []), ConstantTriplet(Value(0, 0, 0))])
		let evaluator = try MSLTreeEvaluator()
		let points = [Coordinate(0.03, h + 0.04), Coordinate(-0.05, h + 0.02)]
		let mirrored = points.map { Coordinate($0.x, 2 * h - $0.y) }
		let a = try evaluator.evaluate(node: node, at: points)
		let b = try evaluator.evaluate(node: node, at: mirrored)
		for (p, q) in zip(a, b) {
			#expect(Swift.abs(p.x - q.x) < 1e-5, "\(p) vs \(q)")
		}
		// Inside the central triangle it's the identity: source x at x.
		let inside = try evaluator.evaluate(node: node, at: [Coordinate(0.01, 0.02)])[0]
		#expect(Swift.abs(inside.x - 0.01) < 1e-6)
	}

	/// The lattice step plus folding must land every point in the central
	/// triangle, even far from the origin, so the output is x at a point
	/// no farther from the origin than the triangle's circumradius.
	@Test func kaleidoscopeFoldsFarPointsIntoTheTriangle() throws {
		let size = 2.1
		let circumradius = (1 / (0.25 + size)) / 3.0.squareRoot()
		let node = try Self.make("kaleidoscope", [Constant(size), Constant(0.4), try Self.make("x", []), ConstantTriplet(Value(0, 0, 0))])
		let far = [Coordinate(37.2, -18.9), Coordinate(-250.5, 400.25), Coordinate(1.3, 1.1)]
		for v in try MSLTreeEvaluator().evaluate(node: node, at: far) {
			#expect(v.x.isFinite && Swift.abs(v.x) <= circumradius + 1e-4, "\(v)")
		}
	}
}

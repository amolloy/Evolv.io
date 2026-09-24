//
//  ExpressionTreeTests.swift
//  ExpressionTreeTests
//
//  Created by Andy Molloy on 6/8/25.
//

import Testing
import Foundation
import simd
@testable import ExpressionTree

struct ExpressionTreeTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

/// Where the real, shipped `.evolvnode` files live in the source tree --
/// shared by `DSLLibraryTests` and `DSLTestNodes` below. Not `Bundle.main`
/// (see DSLLibraryTests' header for why); `#filePath` always resolves
/// relative to this very file's location in the checked-out source tree,
/// regardless of whether this test target happens to be app-hosted.
private func evolvIoBundledNodesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ExpressionTreeTests.swift -> ExpressionTreeTests/
        .deletingLastPathComponent() // -> repo root
        .appendingPathComponent("Evolv.io/Resources/BundledNodes")
}

/// Thin, DSL-backed stand-ins for the Swift node classes (VariableX,
/// VariableY, Add, Mult, Div, Abs, Invert, Round, Log, If, And,
/// RotateVector, HSVToRGB, Dissolve) that used to exist and were
/// convenient to build test trees with -- deleted once their .evolvnode
/// equivalents took over `NodeRegistry` (see the "move everything to DSL"
/// pass). Backed by the real bundled files via `DSLLibrary`, not a
/// hand-rolled parallel implementation, so a bug in a bundled file would
/// show up as a failure here too, not just in its own dedicated
/// golden-value test.
enum DSLTestNodes {
    private static let constructors: [String: NodeRegistry.NodeConstructor] = {
        let (constructors, issues) = DSLLibrary.scan(roots: [evolvIoBundledNodesDirectory()], reservedNames: [])
        precondition(issues.isEmpty, "DSLTestNodes: unexpected load issues: \(issues.map(\.message))")
        return constructors
    }()

    private static func make(_ name: String, _ children: [any Node]) -> any Node {
        guard let constructor = constructors[name] else {
            preconditionFailure("DSLTestNodes: no bundled node named '\(name)' -- was it renamed?")
        }
        return try! constructor(children)
    }

    static func x() -> any Node { make("x", []) }
    static func y() -> any Node { make("y", []) }
    static func add(_ a: any Node, _ b: any Node) -> any Node { make("+", [a, b]) }
    static func mult(_ a: any Node, _ b: any Node) -> any Node { make("*", [a, b]) }
    static func div(_ a: any Node, _ b: any Node) -> any Node { make("/", [a, b]) }
    static func abs(_ a: any Node) -> any Node { make("abs", [a]) }
    static func invert(_ a: any Node) -> any Node { make("invert", [a]) }
    static func round(_ a: any Node, _ b: any Node) -> any Node { make("round", [a, b]) }
    static func log(_ a: any Node, _ b: any Node) -> any Node { make("log", [a, b]) }
    static func ifNode(_ condition: any Node, _ thenVal: any Node, _ elseVal: any Node) -> any Node { make("if", [condition, thenVal, elseVal]) }
    static func and(_ a: any Node, _ b: any Node) -> any Node { make("and", [a, b]) }
    static func rotateVector(_ angle: any Node, _ x: any Node, _ y: any Node) -> any Node { make("rotate-vector", [angle, x, y]) }
    static func hsvToRGB(_ hsv: any Node) -> any Node { make("hsv-to-rgb", [hsv]) }
    static func dissolve(_ v0: any Node, _ w: any Node, _ v1: any Node) -> any Node { make("dissolve", [v0, w, v1]) }
}

/// Regression tests for generated MSL, checked against golden values.
///
/// This suite replaces what was originally a parity suite comparing
/// generated MSL against a parallel Swift `value(at:)` implementation for
/// every node type -- that Swift path no longer exists (see the Metal
/// codegen migration plan's Phase B cutover: NodeRenderer renders via Metal
/// exclusively now, and ExpressionResult/CachedNode/every node's evaluate
/// path were deleted once the parity suite proved the translation correct).
/// The golden values below are that suite's last-known-good output,
/// hand-verified against each node's documented formula at the time they
/// were captured -- see git history for the original Swift-vs-Metal
/// comparison this superseded. This suite's job now is narrower: catch
/// future accidental changes to a node's generated MSL, not prove the
/// original translation. Most node types here are DSL-defined now (see
/// DSLTestNodes above) -- these tests exercise the real bundled files,
/// not a Swift class, so they're now equivalent in spirit to
/// DSLLibraryTests' "bundledXxxMatchesGoldenValue" checks.
struct MetalRenderRegressionTests {
    private static let coord = Coordinate(x: 0.3, y: -0.4)

    private func assertGolden(_ node: any Node, _ expected: Value, tolerance: Double = 1e-4) throws {
        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Self.coord])[0]
        let diff = abs(actual - expected)
        let maxDiff = Swift.max(diff.x, Swift.max(diff.y, diff.z))
        #expect(maxDiff < tolerance, "expected \(expected), got \(actual), maxDiff \(maxDiff)")
    }

    /// `Perlin.permutation` is reshuffled fresh every process launch (by
    /// design -- see Perlin.swift), so any node whose output actually
    /// depends on the noise hash (not just on whether the table loaded/
    /// compiled) has no stable golden value to check across test runs.
    /// This checks the weaker thing that *is* stable: the result is finite
    /// and within noise's defined [0, 1] output range (with a little slack
    /// for float rounding at the edges).
    private func assertFiniteAndInNoiseRange(_ node: any Node) throws {
        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Self.coord])[0]
        for c in 0..<3 {
            #expect(actual[c].isFinite, "component \(c) not finite: \(actual)")
            #expect(actual[c] > -0.01 && actual[c] < 1.01, "component \(c) outside noise's [0,1] range: \(actual)")
        }
    }

    @Test func constant() throws {
        try assertGolden(Constant(0.375), Value(0.375, 0.375, 0.375))
    }

    @Test func constantTriplet() throws {
        try assertGolden(ConstantTriplet(Value(0.1, 0.2, 0.3)), Value(0.1, 0.2, 0.3))
    }

    @Test func variableX() throws {
        try assertGolden(DSLTestNodes.x(), Value(repeating: 0.3))
    }

    @Test func variableY() throws {
        try assertGolden(DSLTestNodes.y(), Value(repeating: -0.4))
    }

    @Test func add() throws {
        try assertGolden(DSLTestNodes.add(DSLTestNodes.x(), DSLTestNodes.y()), Value(repeating: -0.1))
    }

    /// A node referenced twice by object identity within one parent should
    /// still produce correct results under the codegen context's
    /// identity-based dedup (see `MSLCodegenContext`) -- checked here
    /// instead of only by inspection.
    @Test func sharedSubexpression() throws {
        let shared = DSLTestNodes.x()
        try assertGolden(DSLTestNodes.add(shared, shared), Value(repeating: 0.6))
    }

    @Test func mult() throws {
        try assertGolden(DSLTestNodes.mult(DSLTestNodes.x(), DSLTestNodes.y()), Value(repeating: -0.12))
    }

    @Test func div() throws {
        try assertGolden(DSLTestNodes.div(DSLTestNodes.x(), ConstantTriplet(Value(2.0, -3.0, 0.5))), Value(0.15, -0.1, 0.6))
    }

    @Test func absNode() throws {
        try assertGolden(DSLTestNodes.abs(DSLTestNodes.x()), Value(repeating: 0.3))
    }

    @Test func invert() throws {
        try assertGolden(DSLTestNodes.invert(DSLTestNodes.y()), Value(repeating: 1.4))
    }

    @Test func round() throws {
        try assertGolden(DSLTestNodes.round(DSLTestNodes.y(), ConstantTriplet(Value(0.25, 0.5, 1.0))), Value(-0.5, -0.5, 0.0))
    }

    @Test func log() throws {
        try assertGolden(DSLTestNodes.log(DSLTestNodes.y(), ConstantTriplet(Value(0.19, -3.0, 15.5))),
                          Value(0.5517393350601196, -0.8340437412261963, -0.3343101739883423))
    }

    @Test func ifNode() throws {
        try assertGolden(DSLTestNodes.ifNode(DSLTestNodes.x(), ConstantTriplet(Value(1.0, 2.0, 3.0)), ConstantTriplet(Value(-1.0, -2.0, -3.0))),
                          Value(1.0, 2.0, 3.0))
    }

    /// `and` does bitwise AND on raw IEEE-754 bit patterns at 32-bit width
    /// (a real semantic difference from the CPU's 64-bit width, not just
    /// lower precision) -- accepted per the migration plan.
    @Test func and() throws {
        try assertGolden(DSLTestNodes.and(ConstantTriplet(Value(0.75, -0.25, 3.5)), ConstantTriplet(Value(0.5, 0.5, 0.5))),
                          Value(0.5, 0.125, 0.0))
    }

    // Note: this specific coordinate (0.3, -0.4) times bw-noise's internal
    // *50 scale lands exactly on a Perlin grid vertex (3.0, -4.0), where
    // fade(0)=0 collapses the interpolation to a trivial 0.5 regardless of
    // the permutation table's contents -- a valid golden value (it does
    // still catch crashes, wrong offset math, missing-table compile errors)
    // but not a discriminating one for the hash/gradient math itself. Real
    // coverage for that lived in the original parity suite's noiseSafeCoordinates
    // (see git history); not reproduced here since this suite's job is
    // narrower (catch regressions, not re-prove the translation).
    @Test func bwNoise() throws {
        try assertGolden(BWNoise([Constant(0.2), Constant(2)]), Value(0.5, 0.5, 0.5))
    }

    // colorNoise/warpedBWNoise/warpedColorNoise: unlike bwNoise above, these
    // coordinates don't happen to land on a grid vertex, so their actual
    // output legitimately varies run to run with the reshuffled permutation
    // table -- range/sanity checks only, see assertFiniteAndInNoiseRange.
    @Test func colorNoise() throws {
        try assertFiniteAndInNoiseRange(ColorNoise([Constant(0.1), Constant(2)]))
    }

    @Test func warpedBWNoise() throws {
        try assertFiniteAndInNoiseRange(WarpedBWNoise([DSLTestNodes.x(), DSLTestNodes.y(), Constant(0.04), Constant(3)]))
    }

    @Test func warpedColorNoise() throws {
        try assertFiniteAndInNoiseRange(WarpedColorNoise([DSLTestNodes.mult(DSLTestNodes.x(), Constant(0.2)), DSLTestNodes.y(), Constant(0.1), Constant(2)]))
    }

    /// The exact sample expression from ContentView's "(grad-direction
    /// (bw-noise .15 2) .0 .0)" -- real usage, not just a synthetic tree.
    /// Range-checked rather than golden-valued: its source is noise, so its
    /// output legitimately varies with the reshuffled permutation table.
    @Test func gradientDirection() throws {
        try assertFiniteAndInNoiseRange(GradientDirection([BWNoise([Constant(0.15), Constant(2)]), Constant(0.0), Constant(0.0)]))
    }

    /// `source = x²` has constant curvature (2·r² per finite-difference
    /// radius `r`) along x and exactly zero curvature along y (it doesn't
    /// depend on y), independent of the sample coordinate -- so the golden
    /// value here is hand-derived, not just captured from a run: with
    /// `p2 = 0` (curvature weight fully on the x axis), `p3 = 1` (identity
    /// contrast exponent), `color = (1,1,1)`, and the default
    /// `debugDelta/debugHeightFactor/debugTapCount` (0.01/20/4), curvature
    /// averages to `2 * mean((0.01*i/4)^2 for i in 1...4) = 9.375e-5`,
    /// scaled by `heightFactor = 20` gives `t = 0.001875`.
    @Test func colorGradientCurvature() throws {
        let source = DSLTestNodes.mult(DSLTestNodes.x(), DSLTestNodes.x())
        let node = ColorGradientCurvature([source, Constant(3.1), Constant(0.0), ConstantTriplet(Value(1, 1, 1)), Constant(1.0)])
        try assertGolden(node, Value(0.001875, 0.001875, 0.001875))
    }

    @Test func bump() throws {
        let node = Bump([
            DSLTestNodes.x(),
            ConstantTriplet(Value(0.5, 0.5, 0.5)),
            Constant(0.7),
            ConstantTriplet(Value(0.9, 0.1, 0.1)),
            ConstantTriplet(Value(0.1, 0.1, 0.9)),
            Constant(0.3),
            Constant(0.4),
            Constant(0.8)
        ])
        try assertGolden(node, Value(0.10437603294849396, 0.10000000149011612, 0.8956239223480225), tolerance: 1e-3)
    }

    @Test func rotateVector() throws {
        try assertGolden(DSLTestNodes.rotateVector(DSLTestNodes.x(), DSLTestNodes.y(), ConstantTriplet(Value(0.2, -0.3, 0.5))),
                          Value(-0.07331068068742752, -0.47781917452812195, 0.169394388794899))
    }

    @Test func hsvToRGB() throws {
        try assertGolden(DSLTestNodes.hsvToRGB(ConstantTriplet(Value(0.05, 0.8, 0.9))),
                          Value(0.8999999761581421, 0.3960000276565552, 0.18000000715255737))
    }

    @Test func dissolve() throws {
        try assertGolden(DSLTestNodes.dissolve(DSLTestNodes.x(), Constant(0.5), DSLTestNodes.y()), Value(repeating: -0.05))
    }

    /// Regression test for a real bug: a `color-grad` whose own `source`
    /// subtree contains *another* `color-grad` (exactly Figure 9's shape --
    /// see ContentView.sampleExpressions["Figure 9"]) produced two
    /// `emitFunction`-generated MSL functions both named "fn0", since each
    /// nested `MSLCodegenContext` used to keep its own function-name counter
    /// starting at 0 instead of sharing one across the whole codegen pass.
    /// That's a duplicate-definition compile error, which NodeRenderer's
    /// Metal render path silently swallowed by falling back to an all-black
    /// image -- every isolated per-node test above passed throughout,
    /// because none of them nested a color-grad inside another color-grad's
    /// source. Fixed in MSLCodegenContext by sharing one counter across a
    /// context and every sub-context `emitFunction` creates. Built via
    /// DSLCodegenNode (the hand-written ColorGradient Swift class this bug
    /// was originally found against is gone now that "color-grad" is
    /// DSL-defined -- see DSLSampleDefinitions.colorGradTemplate) since
    /// the bug lives in MSLCodegenContext/emitFunction, not in either
    /// implementation of color-grad's own math.
    @Test func nestedColorGradient() throws {
        func colorGrad(_ children: [any Node]) -> DSLCodegenNode {
            DSLCodegenNode(template: DSLSampleDefinitions.colorGradTemplate,
                            params: DSLSampleDefinitions.colorGradParams,
                            modules: ["lighting": DSLSampleDefinitions.lightingModule],
                            children: children)
        }
        let inner = colorGrad([
            DSLTestNodes.round(
                DSLTestNodes.add(DSLTestNodes.y(), DSLTestNodes.log(DSLTestNodes.invert(DSLTestNodes.y()), Constant(15.5))),
                DSLTestNodes.x()
            ),
            Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)
        ])
        let outerSource = DSLTestNodes.round(
            DSLTestNodes.add(
                DSLTestNodes.abs(
                    DSLTestNodes.round(
                        DSLTestNodes.log(DSLTestNodes.add(DSLTestNodes.y(), inner), Constant(0.19)),
                        DSLTestNodes.x()
                    )
                ),
                DSLTestNodes.log(DSLTestNodes.invert(DSLTestNodes.y()), Constant(15.5))
            ),
            DSLTestNodes.x()
        )
        let outer = colorGrad([outerSource, Constant(3.1), Constant(1.9), ConstantTriplet(Value(0.95, 0.7, 0.35)), Constant(1.35)])
        let figure9 = DSLTestNodes.round(DSLTestNodes.log(DSLTestNodes.add(DSLTestNodes.y(), outer), Constant(0.19)), DSLTestNodes.x())

        // Coordinates kept away from x=0 (round(_, x) divides by it) and off
        // exact Perlin-adjacent boundaries, same hazard class as this
        // suite's other color-grad-involving cases.
        let coords: [Coordinate] = [Coordinate(x: 0.4, y: -0.6), Coordinate(x: -0.3, y: 0.2), Coordinate(x: 0.7, y: 0.5)]
        let evaluator = try MSLTreeEvaluator()
        let values = try evaluator.evaluate(node: figure9, at: coords)

        var sawNonZero = false
        for (i, v) in values.enumerated() {
            #expect(v.x.isFinite && v.y.isFinite && v.z.isFinite, "coordinate \(i) (\(coords[i])) not finite: \(v)")
            if v != Value.zero { sawNonZero = true }
        }
        // The specific bug this guards against makes MetalRenderContext's
        // compile throw and NodeRenderer substitute an all-zero (black)
        // buffer -- MSLTreeEvaluator itself would instead just throw here
        // (caught above as a test failure), so this is really guarding
        // against the underlying name collision recurring in some other
        // shape, not the black-fallback specifically. Kept as a sanity
        // check that the tree isn't degenerately all-zero regardless.
        #expect(sawNonZero, "figure 9's tree evaluated to all zeros across every sample coordinate")
    }
}

/// Golden-value checks against `DSLSampleDefinitions`' embedded copies of
/// "mod"/"color-grad" (one simple node, one that exercises every hard case:
/// a sampled-function child, a requires() clause, and a dynamic tap-count
/// reduction) -- kept separate from the *real*
/// Evolv.io/Resources/BundledNodes/{mod,color-grad}.evolvnode files (see
/// DSLLibraryTests below) so these checks don't depend on
/// bundle-resource-copying working correctly on the test target.
struct DSLSpikeTests {
    private static let coord = Coordinate(x: 0.3, y: -0.4)

    @Test func dslMod() throws {
        let node = DSLCodegenNode(template: DSLSampleDefinitions.modTemplate,
                                   children: [DSLTestNodes.y(), ConstantTriplet(Value(0.0, 0.3, -0.4))])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Self.coord])[0]
        let expected = Value(-0.4, 0.2, 0.0)
        let diff = abs(actual - expected)
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-4, "expected \(expected), got \(actual)")
    }

    /// Figure 9's inner `color-grad` call, same tree and golden value as
    /// MetalRenderRegressionTests.colorGradient() above -- params match
    /// ColorGradient's current debugDelta/debugHeightFactor/debugLightZ/
    /// debugTapCount defaults (0.01/20.0/0.0/4), same as
    /// DSLSampleDefinitions.colorGradParams.
    @Test func dslColorGradient() throws {
        let source = DSLTestNodes.round(
            DSLTestNodes.add(DSLTestNodes.y(), DSLTestNodes.log(DSLTestNodes.invert(DSLTestNodes.y()), Constant(15.5))),
            DSLTestNodes.x()
        )
        let node = DSLCodegenNode(template: DSLSampleDefinitions.colorGradTemplate,
                                   params: DSLSampleDefinitions.colorGradParams,
                                   modules: ["lighting": DSLSampleDefinitions.lightingModule],
                                   children: [source, Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Self.coord])[0]
        let expected = Value(0.03680462762713432, 0.024370135739445686, 0.0193475428968668)
        let diff = abs(actual - expected)
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-3, "expected \(expected), got \(actual)")
    }
}

/// Tests for `DSLLibrary`'s scanning/collision logic itself, plus a check
/// that the real, shipped `Evolv.io/Resources/BundledNodes/*.evolvnode`
/// files (not `DSLSampleDefinitions`' embedded copies) parse cleanly and
/// produce correct output. Locates that real folder via `#filePath` rather
/// than `Bundle.main` -- this test target may or may not be hosted inside
/// the app bundle depending on scheme configuration, so `Bundle.main` isn't
/// a reliable way to find app resources from here, but the source tree's
/// layout relative to this very file always is.
struct DSLLibraryTests {
    private static var bundledNodesDirectory: URL { evolvIoBundledNodesDirectory() }

    @Test func bundledNodesLoadWithoutIssues() throws {
        let (constructors, issues) = DSLLibrary.scan(roots: [Self.bundledNodesDirectory], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        #expect(constructors["mod"] != nil)
        #expect(constructors["color-grad"] != nil)
    }

    /// Same golden value as DSLSpikeTests.dslMod() above -- proves the real
    /// shipped file, not just the embedded test copy, is correct.
    @Test func bundledModMatchesGoldenValue() throws {
        let (constructors, _) = DSLLibrary.scan(roots: [Self.bundledNodesDirectory], reservedNames: [])
        let node = try constructors["mod"]!([DSLTestNodes.y(), ConstantTriplet(Value(0.0, 0.3, -0.4))])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0.3, y: -0.4)])[0]
        let expected = Value(-0.4, 0.2, 0.0)
        let diff = abs(actual - expected)
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-4, "expected \(expected), got \(actual)")
    }

    /// Same golden value as DSLSpikeTests.dslColorGradient() above -- proves
    /// the real shipped color-grad.evolvnode file, resolving its
    /// requires(lighting) against the real bundled lighting.evolvnode
    /// module (not DSLSampleDefinitions' embedded copies of either), is
    /// correct end-to-end -- including the name-mangling that makes it
    /// safe alongside a hand-written node's intrinsic lighting helpers.
    @Test func bundledColorGradMatchesGoldenValue() throws {
        let (constructors, issues) = DSLLibrary.scan(roots: [Self.bundledNodesDirectory], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let source = DSLTestNodes.round(
            DSLTestNodes.add(DSLTestNodes.y(), DSLTestNodes.log(DSLTestNodes.invert(DSLTestNodes.y()), Constant(15.5))),
            DSLTestNodes.x()
        )
        let node = try constructors["color-grad"]!([source, Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0.3, y: -0.4)])[0]
        let expected = Value(0.03680462762713432, 0.024370135739445686, 0.0193475428968668)
        let diff = abs(actual - expected)
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-3, "expected \(expected), got \(actual)")
    }

    /// The exact bug class Figure 10 hit in the real app: a hand-written
    /// node needing the intrinsic lighting helpers (`Bump`, via
    /// `context.require(.lightingHelpers)`) combined with a DSL node
    /// requiring the real, separately-text "lighting" module
    /// (`color-grad`), in one tree/kernel. Before name-mangling existed
    /// this failed to compile with "redefinition of 'avgLum'" -- Metal
    /// throws on that (caught below as a test failure, not a crash), so
    /// this is a real, mechanical guard against the bug recurring, not
    /// just a description of what used to go wrong.
    @Test func handWrittenAndDSLLightingNodesCoexistInOneTree() throws {
        let (constructors, issues) = DSLLibrary.scan(roots: [Self.bundledNodesDirectory], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let colorGradConstructor = try #require(constructors["color-grad"])
        let colorGrad = try colorGradConstructor([
            DSLTestNodes.round(
                DSLTestNodes.add(DSLTestNodes.y(), DSLTestNodes.log(DSLTestNodes.invert(DSLTestNodes.y()), Constant(15.5))),
                DSLTestNodes.x()
            ),
            Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)
        ])
        let bump = Bump([
            DSLTestNodes.x(),
            ConstantTriplet(Value(0.5, 0.5, 0.5)),
            Constant(0.7),
            ConstantTriplet(Value(0.9, 0.1, 0.1)),
            ConstantTriplet(Value(0.1, 0.1, 0.9)),
            Constant(0.3),
            Constant(0.4),
            Constant(0.8)
        ])
        let combined = DSLTestNodes.add(colorGrad, bump)

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: combined, at: [Coordinate(x: 0.3, y: -0.4)])[0]
        #expect(actual.x.isFinite && actual.y.isFinite && actual.z.isFinite, "non-finite result: \(actual)")
    }

    /// The general case, not just the "lighting" one: two independently-
    /// authored modules that both happen to define a function called
    /// `helper`, each required by a different node, both in one tree.
    /// Checks an actual numeric result (not just "didn't crash") to prove
    /// each node's call really reaches *its own* module's `helper`, not
    /// the other one's.
    @Test func twoModulesWithCollidingFunctionNamesCoexistInOneTree() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try """
        module "module-a" {
            func helper(v: float3) -> float3 {
                return v * 2.0
            }
        }
        """.write(to: tempDir.appendingPathComponent("module-a.evolvnode"), atomically: true, encoding: .utf8)
        try """
        module "module-b" {
            func helper(v: float3) -> float3 {
                return v * 3.0
            }
        }
        """.write(to: tempDir.appendingPathComponent("module-b.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "fixture-uses-a"(v0) requires("module-a") {
            return helper(v0)
        }
        """.write(to: tempDir.appendingPathComponent("fixture-uses-a.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "fixture-uses-b"(v0) requires("module-b") {
            return helper(v0)
        }
        """.write(to: tempDir.appendingPathComponent("fixture-uses-b.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let usesA = try #require(constructors["fixture-uses-a"])
        let usesB = try #require(constructors["fixture-uses-b"])
        let combined = DSLTestNodes.add(try usesA([Constant(1.0)]), try usesB([Constant(1.0)]))

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: combined, at: [Coordinate(x: 0, y: 0)])[0]
        // module-a's helper(1) = 2, module-b's helper(1) = 3, combined = 5.
        #expect(actual == Value(repeating: 5.0))
    }

    @Test func nameCollidingWithAReservedBuiltinIsReportedNotRegistered() throws {
        let (constructors, issues) = DSLLibrary.scan(roots: [Self.bundledNodesDirectory], reservedNames: ["mod"])
        #expect(constructors["mod"] == nil)
        #expect(issues.contains { $0.message.contains("mod") })
    }

    @Test func scanRecursesIntoSubfolders() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let subDir = tempDir.appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        try """
        node "fixture-add"(v0, v1) {
            return v0 + v1
        }
        """.write(to: subDir.appendingPathComponent("fixture-add.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        #expect(constructors["fixture-add"] != nil)
    }

    /// Two loose files in the same root both declaring `node "dup"` --
    /// deterministic scan order (alphabetical by path) means "a.evolvnode"
    /// wins and "b.evolvnode" is reported, not silently dropped or crashed.
    @Test func duplicateNameWithinOneRootReportsTheLaterFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try """
        node "dup"(v0) {
            return v0
        }
        """.write(to: tempDir.appendingPathComponent("a.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "dup"(v0, v1) {
            return v0 + v1
        }
        """.write(to: tempDir.appendingPathComponent("b.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(constructors["dup"] != nil)
        #expect(issues.count == 1)
        #expect(issues.first?.fileURL.lastPathComponent == "b.evolvnode")
    }

    /// A node `requires()`ing a module, both loose files in the same root
    /// -- proves the module gets parsed, turned into real MSL, spliced
    /// into the kernel, and actually called (not just that scanning
    /// doesn't error).
    @Test func moduleRequirementResolvesAndProducesCorrectOutput() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try """
        module "double-helpers" {
            func doubleIt(v: float3) -> float3 {
                return v * 2.0
            }
        }
        """.write(to: tempDir.appendingPathComponent("double-helpers.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "fixture-double"(v0) requires("double-helpers") {
            return doubleIt(v0)
        }
        """.write(to: tempDir.appendingPathComponent("fixture-double.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let constructor = try #require(constructors["fixture-double"])
        let node = try constructor([Constant(3.0)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0, y: 0)])[0]
        #expect(actual == Value(repeating: 6.0))
    }

    /// A `requires()` naming a module that was never found -- reported per
    /// file, that node isn't registered, and (crucially) nothing traps.
    @Test func unresolvedRequiresIsReportedNotCrashed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try """
        node "fixture-orphan"(v0) requires("nonexistent-module") {
            return v0
        }
        """.write(to: tempDir.appendingPathComponent("fixture-orphan.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(constructors["fixture-orphan"] == nil)
        #expect(issues.contains { $0.message.contains("nonexistent-module") })
    }

    /// `param $factor: float = 2.0` with no external override -- resolved
    /// purely from the file's own default (the only path a library-loaded
    /// node can take, since NodeRegistry's constructor closures have no
    /// slot for external params -- that's what `param` defaults are for).
    @Test func paramDefaultIsUsedWhenNoExternalValueSupplied() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try """
        node "fixture-scale"(v0) {
            param $factor: float = 2.0
            return v0 * $factor
        }
        """.write(to: tempDir.appendingPathComponent("fixture-scale.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let constructor = try #require(constructors["fixture-scale"])
        let node = try constructor([Constant(0.3)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0, y: 0)])[0]
        let diff = abs(actual - Value(repeating: 0.6))
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-6)
    }

    /// Same template as above, but constructed directly (bypassing
    /// DSLLibrary, which has no way to inject external params through a
    /// bare Lisp expression) -- proves DSLCodegenNode's `effectiveParams`
    /// merge really does let an external value win over the file's own
    /// default, for whatever future caller does have one to supply
    /// (mirrors DSLSampleDefinitions.colorGradParams's usage today).
    @Test func externalParamOverridesInFileDefault() throws {
        let template = try DSLParser("""
        node "fixture-scale"(v0) {
            param $factor: float = 2.0
            return v0 * $factor
        }
        """).parseTemplate()
        let node = DSLCodegenNode(template: template, params: ["factor": .float(10.0)], children: [Constant(0.3)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0, y: 0)])[0]
        let diff = abs(actual - Value(repeating: 3.0))
        #expect(Swift.max(diff.x, Swift.max(diff.y, diff.z)) < 1e-6)
    }

    /// Two subfolders, each with its own `Package.evolvnode`, each
    /// defining a node with the *same* bare name -- without namespacing
    /// this would be a collision; with it, both register distinctly and
    /// the bare name itself is never claimed by either.
    @Test func packageManifestsNamespaceNodesToAvoidCollision() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let aliceDir = tempDir.appendingPathComponent("AliceStuff")
        let bobDir = tempDir.appendingPathComponent("BobStuff")
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bobDir, withIntermediateDirectories: true)

        try #"package "alice""#.write(to: aliceDir.appendingPathComponent("Package.evolvnode"), atomically: true, encoding: .utf8)
        try #"package "bob""#.write(to: bobDir.appendingPathComponent("Package.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "warp"(v0) {
            return v0
        }
        """.write(to: aliceDir.appendingPathComponent("warp.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "warp"(v0) {
            return v0
        }
        """.write(to: bobDir.appendingPathComponent("warp.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        #expect(constructors["alice.warp"] != nil)
        #expect(constructors["bob.warp"] != nil)
        #expect(constructors["warp"] == nil)
    }

    /// A node's bare `requires(helpers)` resolves against a module in its
    /// *own* namespaced folder (both under the same `Package.evolvnode`),
    /// without needing the requirement written out fully-qualified.
    @Test func requiresResolvesAgainstModuleInSameNamespace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let aliceDir = tempDir.appendingPathComponent("Alice")
        try FileManager.default.createDirectory(at: aliceDir, withIntermediateDirectories: true)

        try #"package "alice""#.write(to: aliceDir.appendingPathComponent("Package.evolvnode"), atomically: true, encoding: .utf8)
        try """
        module "helpers" {
            func triple(v: float3) -> float3 {
                return v * 3.0
            }
        }
        """.write(to: aliceDir.appendingPathComponent("helpers.evolvnode"), atomically: true, encoding: .utf8)
        try """
        node "fixture-triple"(v0) requires(helpers) {
            return triple(v0)
        }
        """.write(to: aliceDir.appendingPathComponent("fixture-triple.evolvnode"), atomically: true, encoding: .utf8)

        let (constructors, issues) = DSLLibrary.scan(roots: [tempDir], reservedNames: [])
        #expect(issues.isEmpty, "unexpected load issues: \(issues.map(\.message))")
        let constructor = try #require(constructors["alice.fixture-triple"])
        let node = try constructor([Constant(2.0)])

        let evaluator = try MSLTreeEvaluator()
        let actual = try evaluator.evaluate(node: node, at: [Coordinate(x: 0, y: 0)])[0]
        #expect(actual == Value(repeating: 6.0))
    }
}

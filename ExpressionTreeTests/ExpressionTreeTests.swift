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
/// original translation.
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
        try assertGolden(VariableX(), Value(repeating: 0.3))
    }

    @Test func variableY() throws {
        try assertGolden(VariableY(), Value(repeating: -0.4))
    }

    @Test func add() throws {
        try assertGolden(Add([VariableX(), VariableY()]), Value(repeating: -0.1))
    }

    /// A node referenced twice by object identity within one parent should
    /// still produce correct results under the codegen context's
    /// identity-based dedup (see `MSLCodegenContext`) -- checked here
    /// instead of only by inspection.
    @Test func sharedSubexpression() throws {
        let shared = VariableX()
        try assertGolden(Add([shared, shared]), Value(repeating: 0.6))
    }

    @Test func mult() throws {
        try assertGolden(Mult([VariableX(), VariableY()]), Value(repeating: -0.12))
    }

    @Test func div() throws {
        try assertGolden(Div([VariableX(), ConstantTriplet(Value(2.0, -3.0, 0.5))]), Value(0.15, -0.1, 0.6))
    }

    /// One component of the divisor is exactly zero, exercising Mod's
    /// zero-divisor masking branch (not just the plain-fmod path).
    @Test func mod() throws {
        try assertGolden(Mod([VariableY(), ConstantTriplet(Value(0.0, 0.3, -0.4))]), Value(-0.4, 0.2, 0.0))
    }

    @Test func absNode() throws {
        try assertGolden(Abs([VariableX()]), Value(repeating: 0.3))
    }

    @Test func invert() throws {
        try assertGolden(Invert([VariableY()]), Value(repeating: 1.4))
    }

    @Test func round() throws {
        try assertGolden(Round([VariableY(), ConstantTriplet(Value(0.25, 0.5, 1.0))]), Value(-0.5, -0.5, 0.0))
    }

    @Test func log() throws {
        try assertGolden(Log([VariableY(), ConstantTriplet(Value(0.19, -3.0, 15.5))]),
                          Value(0.5517393350601196, -0.8340437412261963, -0.3343101739883423))
    }

    @Test func ifNode() throws {
        try assertGolden(If([VariableX(), ConstantTriplet(Value(1.0, 2.0, 3.0)), ConstantTriplet(Value(-1.0, -2.0, -3.0))]),
                          Value(1.0, 2.0, 3.0))
    }

    /// `and` does bitwise AND on raw IEEE-754 bit patterns at 32-bit width
    /// (a real semantic difference from the CPU's 64-bit width, not just
    /// lower precision) -- accepted per the migration plan.
    @Test func and() throws {
        try assertGolden(And([ConstantTriplet(Value(0.75, -0.25, 3.5)), ConstantTriplet(Value(0.5, 0.5, 0.5))]),
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
        try assertFiniteAndInNoiseRange(WarpedBWNoise([VariableX(), VariableY(), Constant(0.04), Constant(3)]))
    }

    @Test func warpedColorNoise() throws {
        try assertFiniteAndInNoiseRange(WarpedColorNoise([Mult([VariableX(), Constant(0.2)]), VariableY(), Constant(0.1), Constant(2)]))
    }

    /// The exact sample expression from ContentView's "(grad-direction
    /// (bw-noise .15 2) .0 .0)" -- real usage, not just a synthetic tree.
    /// Range-checked rather than golden-valued: its source is noise, so its
    /// output legitimately varies with the reshuffled permutation table.
    @Test func gradientDirection() throws {
        try assertFiniteAndInNoiseRange(GradientDirection([BWNoise([Constant(0.15), Constant(2)]), Constant(0.0), Constant(0.0)]))
    }

    /// Figure 9's inner `color-grad` call, verbatim: `(color-grad (round (+ y
    /// (log (invert y) 15.5)) x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)`.
    @Test func colorGradient() throws {
        let source = Round([
            Add([VariableY(), Log([Invert([VariableY()]), Constant(15.5)])]),
            VariableX()
        ])
        let node = ColorGradient([source, Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)])
        try assertGolden(node, Value(0.03680462762713432, 0.024370135739445686, 0.0193475428968668), tolerance: 1e-3)
    }

    @Test func bump() throws {
        let node = Bump([
            VariableX(),
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
        try assertGolden(RotateVector([VariableX(), VariableY(), ConstantTriplet(Value(0.2, -0.3, 0.5))]),
                          Value(-0.07331068068742752, -0.47781917452812195, 0.169394388794899))
    }

    @Test func hsvToRGB() throws {
        try assertGolden(HSVToRGB([ConstantTriplet(Value(0.05, 0.8, 0.9))]),
                          Value(0.8999999761581421, 0.3960000276565552, 0.18000000715255737))
    }

    @Test func dissolve() throws {
        try assertGolden(Dissolve([VariableX(), Constant(0.5), VariableY()]), Value(repeating: -0.05))
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
    /// context and every sub-context `emitFunction` creates.
    @Test func nestedColorGradient() throws {
        let inner = ColorGradient([
            Round([Add([VariableY(), Log([Invert([VariableY()]), Constant(15.5)])]), VariableX()]),
            Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)
        ])
        let outerSource = Round([
            Add([Abs([Round([Log([Add([VariableY(), inner]), Constant(0.19)]), VariableX()])]),
                 Log([Invert([VariableY()]), Constant(15.5)])]),
            VariableX()
        ])
        let outer = ColorGradient([outerSource, Constant(3.1), Constant(1.9), ConstantTriplet(Value(0.95, 0.7, 0.35)), Constant(1.35)])
        let figure9 = Round([Log([Add([VariableY(), outer]), Constant(0.19)]), VariableX()])

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

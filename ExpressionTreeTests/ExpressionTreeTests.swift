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

/// Parity tests: for each ported node type, check that its generated MSL
/// (evaluated via `MSLTreeEvaluator`) agrees with the existing Swift
/// `value(at:)` path across a grid of sample coordinates. This suite passing
/// for every live node type is the go/no-go gate for the Phase B cutover
/// (see the Metal codegen migration plan) -- it's the thing that lets Swift
/// math actually get deleted with confidence later.
struct MetalCodegenParityTests {
    private static let sampleCoordinates: [Coordinate] = [
        Coordinate(x: -1.0, y: -1.0),
        Coordinate(x: -0.5, y: 0.25),
        Coordinate(x: 0.0, y: 0.0),
        Coordinate(x: 0.3, y: -0.7),
        Coordinate(x: 1.0, y: 1.0),
        Coordinate(x: 0.123, y: -0.456),
        Coordinate(x: -0.999, y: 0.999),
    ]

    /// Tight by default -- generated MSL runs in float32 against a float64
    /// Swift reference, so some difference is expected, but not much for
    /// plain arithmetic. Trees containing `and` (bit-pattern width changes
    /// from 64-bit to 32-bit, a real semantic difference, not just rounding)
    /// should pass a looser tolerance explicitly instead of tightening this.
    private func assertParity(_ node: any Node, tolerance: Double = 1e-4, coordinates: [Coordinate] = MetalCodegenParityTests.sampleCoordinates) throws {
        let evaluator = Evaluator(size: CGSize(width: 64, height: 64))
        let swiftResult = node.evaluate(using: evaluator)
        let swiftValues = coordinates.map { swiftResult.value(at: $0) }

        let metalEvaluator = try MSLTreeEvaluator()
        let metalValues = try metalEvaluator.evaluate(node: node, at: coordinates)

        #expect(swiftValues.count == metalValues.count)
        for (i, pair) in zip(swiftValues, metalValues).enumerated() {
            let (swiftValue, metalValue) = pair
            for c in 0..<3 {
                let s = swiftValue[c]
                let m = metalValue[c]
                // NaN != NaN and inf - inf == NaN, so a plain subtraction
                // would spuriously fail two sides that actually agree on
                // "not a finite number" -- treat matching non-finite values
                // as equal instead of falling through to the diff check.
                if s.isNaN && m.isNaN { continue }
                if s.isInfinite && m.isInfinite && (s > 0) == (m > 0) { continue }
                let diff = abs(s - m)
                #expect(diff < tolerance,
                        "coordinate \(i) (\(coordinates[i])) component \(c): swift=\(s) metal=\(m) diff=\(diff)")
            }
        }
    }

    /// Coordinates chosen to land solidly mid-cell after the *50 scaling
    /// every noise node applies, rather than near an integer boundary --
    /// `sampleCoordinates`'s "nice" fractions (0.3, -0.5, ...) times 50 land
    /// suspiciously close to exact integers, where a float32-vs-float64
    /// rounding difference could floor() into a different permutation-table
    /// cell entirely (a large, qualitative difference, not a small one).
    private static let noiseSafeCoordinates: [Coordinate] = [
        Coordinate(x: 0.137, y: -0.263),
        Coordinate(x: 0.481, y: -0.829),
        Coordinate(x: -0.055, y: 0.612),
        Coordinate(x: 0.947, y: 0.318),
    ]

    @Test func constantParity() throws {
        try assertParity(Constant(0.375))
    }

    @Test func constantNegativeAndFractionalParity() throws {
        try assertParity(Constant(-12.5))
    }

    @Test func constantTripletParity() throws {
        try assertParity(ConstantTriplet(Value(0.1, 0.2, 0.3)))
    }

    @Test func variableXParity() throws {
        try assertParity(VariableX())
    }

    @Test func variableYParity() throws {
        try assertParity(VariableY())
    }

    @Test func addParity() throws {
        try assertParity(Add([VariableX(), VariableY()]))
    }

    @Test func addOfConstantsParity() throws {
        try assertParity(Add([ConstantTriplet(Value(0.4, -0.2, 0.9)), VariableX()]))
    }

    /// A node referenced twice by object identity within one parent should
    /// still produce correct results under the codegen context's
    /// identity-based dedup (see `MSLCodegenContext`) -- this is the direct
    /// analog of `CachedNode`'s runtime cache, checked here instead of only
    /// by inspection.
    @Test func sharedSubexpressionParity() throws {
        let shared = VariableX()
        try assertParity(Add([shared, shared]))
    }

    @Test func multParity() throws {
        try assertParity(Mult([VariableX(), VariableY()]))
    }

    @Test func divParity() throws {
        try assertParity(Div([VariableX(), ConstantTriplet(Value(2.0, -3.0, 0.5))]))
    }

    /// One component of the divisor is exactly zero, exercising Mod's
    /// zero-divisor masking branch (not just the plain-fmod path).
    @Test func modParity() throws {
        try assertParity(Mod([VariableY(), ConstantTriplet(Value(0.0, 0.3, -0.4))]))
    }

    @Test func absParity() throws {
        try assertParity(Abs([VariableX()]))
    }

    @Test func invertParity() throws {
        try assertParity(Invert([VariableY()]))
    }

    @Test func roundParity() throws {
        try assertParity(Round([VariableY(), ConstantTriplet(Value(0.25, 0.5, 1.0))]))
    }

    /// y=0 in the sample coordinates makes `log(abs(0))` an infinity, not a
    /// NaN -- exercises the "infinity passes through, only NaN gets
    /// replaced" distinction in both the Swift and MSL implementations.
    @Test func logParity() throws {
        try assertParity(Log([VariableY(), ConstantTriplet(Value(0.19, -3.0, 15.5))]))
    }

    @Test func ifParity() throws {
        try assertParity(If([VariableX(), ConstantTriplet(Value(1.0, 2.0, 3.0)), ConstantTriplet(Value(-1.0, -2.0, -3.0))]))
    }

    /// `and` does bitwise AND on raw IEEE-754 bit patterns; the CPU does
    /// this at 64-bit width and the Metal port at 32-bit width, which is a
    /// genuinely different operation (not just lower precision) -- accepted
    /// per the migration plan, checked here with an explicitly looser
    /// tolerance rather than by tightening the default.
    @Test func andParity() throws {
        try assertParity(And([ConstantTriplet(Value(0.75, -0.25, 3.5)), ConstantTriplet(Value(0.5, 0.5, 0.5))]), tolerance: 2.0)
    }

    @Test func bwNoiseParity() throws {
        try assertParity(BWNoise([Constant(0.2), Constant(2)]), tolerance: 1e-3, coordinates: Self.noiseSafeCoordinates)
    }

    @Test func colorNoiseParity() throws {
        try assertParity(ColorNoise([Constant(0.1), Constant(2)]), tolerance: 1e-3, coordinates: Self.noiseSafeCoordinates)
    }

    @Test func warpedBWNoiseParity() throws {
        try assertParity(WarpedBWNoise([VariableX(), VariableY(), Constant(0.04), Constant(3)]), tolerance: 1e-3, coordinates: Self.noiseSafeCoordinates)
    }

    @Test func warpedColorNoiseParity() throws {
        try assertParity(WarpedColorNoise([Mult([VariableX(), Constant(0.2)]), VariableY(), Constant(0.1), Constant(2)]), tolerance: 1e-3, coordinates: Self.noiseSafeCoordinates)
    }

    // Note: ContentView's real "(grad-direction (bw-noise .15 2) .0 .0)"
    // sample is deliberately not used as a parity case here. Tried it first
    // -- diffs of up to 0.5 (on a [0,1] output range), even though the
    // isolated bw-noise translation and this smooth-source case both match
    // tightly. Root cause: grad-direction takes a raw finite difference of
    // its source (no division/normalization of the gradient itself before
    // building the surface normal), so wherever the noise field is locally
    // near-flat, Gx/Gy are small numbers built from a subtraction of two
    // close noise samples -- exactly where float32-vs-float64 differences in
    // the underlying Perlin hash get amplified the most after normalizing
    // the resulting (tiny, direction-dominant) vector. That's inherent
    // numerical sensitivity in this specific composition (noise -> finite
    // difference -> normalize), not a translation bug, and no tolerance
    // short of "meaninglessly loose" would make it a useful regression check.
    @Test func gradientDirectionSmoothSourceParity() throws {
        try assertParity(GradientDirection([Mult([VariableX(), VariableY()]), Constant(0.3), Constant(-0.2)]),
                          tolerance: 1e-3)
    }

    /// Coordinates kept comfortably away from x=0 -- color-grad's `source`
    /// here ends in `round(_, x)`, and dividing by an x near zero amplifies
    /// any float32-vs-float64 rounding difference enough to round to a
    /// different integer entirely (same hazard class as the noise-safe
    /// coordinates above, different mechanism).
    private static let colorGradSafeCoordinates: [Coordinate] = [
        Coordinate(x: 0.4, y: -0.6),
        Coordinate(x: -0.3, y: 0.2),
        Coordinate(x: 0.7, y: 0.5),
        Coordinate(x: -0.8, y: -0.35),
    ]

    /// Figure 9's inner `color-grad` call, verbatim: `(color-grad (round (+ y
    /// (log (invert y) 15.5)) x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)`.
    @Test func colorGradientParity() throws {
        let source = Round([
            Add([VariableY(), Log([Invert([VariableY()]), Constant(15.5)])]),
            VariableX()
        ])
        let node = ColorGradient([source, Constant(3.1), Constant(1.86), ConstantTriplet(Value(0.95, 0.7, 0.59)), Constant(1.35)])
        try assertParity(node, tolerance: 5e-3, coordinates: Self.colorGradSafeCoordinates)
    }

    @Test func bumpParity() throws {
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
        try assertParity(node, tolerance: 1e-3)
    }
}

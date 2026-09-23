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
    private func assertParity(_ node: any Node, tolerance: Double = 1e-4) throws {
        let evaluator = Evaluator(size: CGSize(width: 64, height: 64))
        let swiftResult = node.evaluate(using: evaluator)
        let swiftValues = Self.sampleCoordinates.map { swiftResult.value(at: $0) }

        let metalEvaluator = try MSLTreeEvaluator()
        let metalValues = try metalEvaluator.evaluate(node: node, at: Self.sampleCoordinates)

        #expect(swiftValues.count == metalValues.count)
        for (i, pair) in zip(swiftValues, metalValues).enumerated() {
            let (swiftValue, metalValue) = pair
            let diff = abs(swiftValue - metalValue)
            let maxDiff = Swift.max(diff.x, Swift.max(diff.y, diff.z))
            #expect(maxDiff < tolerance,
                    "coordinate \(i) (\(Self.sampleCoordinates[i])): swift=\(swiftValue) metal=\(metalValue) maxDiff=\(maxDiff)")
        }
    }

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
}

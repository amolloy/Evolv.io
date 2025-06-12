//
//  ColorGradient.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import Foundation
import simd

public final class ColorGradient: Node {
	public static var name: String {
		return "color-grad"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 5)
		self.children = children
	}

    public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
        let childResults = children.map { $0.evaluate(using: evaluator) }

        return ColorGradientResult(
            inputSource:    childResults[0],
            offsetSource:   childResults[1],
            rangeSource:    childResults[2],
            centerSource:   childResults[3],
            phaseSource:    childResults[4]
        )
    }
}


/// The ExpressionResult for ColorGradNode that performs the palette calculation.
private struct ColorGradientResult: ExpressionResult {
    let inputSource: any ExpressionResult
    let offsetSource: any ExpressionResult
    let rangeSource: any ExpressionResult
    let centerSource: any ExpressionResult
    let phaseSource: any ExpressionResult

    // Define the phase shifts for R, G, and B to create color separation.
    // These values represent 0, 1/3, and 2/3 of a full cycle.
    private static let phaseShifts = Value(0.0, 0.333, 0.666)

	func sampleBilinear(at coord: Coordinate) -> Value {
        let input = inputSource.sampleBilinear(at: coord).averageLuminance()
        let offset = offsetSource.sampleBilinear(at: coord).averageLuminance()
        let range = rangeSource.sampleBilinear(at: coord).averageLuminance()
        let phase = phaseSource.sampleBilinear(at: coord).averageLuminance()

        let centerColor = centerSource.sampleBilinear(at: coord)

        let angle = (input + offset) * phase * 2.0 * .pi
        let angles = Value(repeating: angle) + Self.phaseShifts * 2.0 * .pi
        let cosVector = Value(cos(angles.x), cos(angles.y), cos(angles.z))
        return centerColor + range * cosVector
    }
}


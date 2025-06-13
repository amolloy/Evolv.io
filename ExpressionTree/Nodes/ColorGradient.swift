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

	func value(at coord: Coordinate) -> Value {
		let input = inputSource.value(at: coord)
		let offset = offsetSource.value(at: coord)
		let range = rangeSource.value(at: coord)
		let phase = phaseSource.value(at: coord)
		let centerColor = centerSource.value(at: coord)

		let angle = (input + offset) * phase * 2.0 * .pi
		let angles = angle * 2.0 * .pi
		let cosVector = cos(angles)
		return centerColor + range * cosVector
    }
}


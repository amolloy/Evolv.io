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
            e0:childResults[0],
            e1:childResults[1],
            e2:childResults[2],
            e3:childResults[3],
            e4:childResults[4]
        )
    }
}


/// The ExpressionResult for ColorGradNode that performs the palette calculation.
private struct ColorGradientResult: ExpressionResult {
    let e0: any ExpressionResult
    let e1: any ExpressionResult
    let e2: any ExpressionResult
    let e3: any ExpressionResult
    let e4: any ExpressionResult

	func value(at coord: Coordinate) -> Value {
		let e0v = e0.value(at: coord)
		let e1v = e1.value(at: coord)
		let e2v = e2.value(at: coord)
		let e3v = e3.value(at: coord)
		let e4v = e4.value(at: coord)

		return sin(e0v * e1v + e2v * e3v) * e4v
    }
}


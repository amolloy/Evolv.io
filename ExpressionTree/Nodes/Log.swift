//
//  Log.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

public class Log: Node {
	public static var name: String {
		return "log"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		if let cachedResult = evaluator.result(for: self) {
			return cachedResult
		}

		assert(children.count == 2)
		let result = LogResult(children.map { $0.evaluate(using: evaluator) })

		evaluator.setResult(result, for: self)

		return result
	}
}

class LogResult: ExpressionResult {
	let e0: ExpressionResult
	let e1: ExpressionResult

	init(_ es: [ExpressionResult]) {
		assert(es.count == 2)
		self.e0 = es[0]
		self.e1 = es[1]
	}

	func value(at coord: Coordinate) -> Value {
		let inputBase = e0.value(at: coord)
		let inputValue = e1.value(at: coord)

		var resultVector = Value.zero

		for i in 0..<3 {
			let safeValue = max(epsilon, inputValue[i])

			var safeBase = max(epsilon, inputBase[i])
			if abs(safeBase - 1.0) < epsilon {
				safeBase = 1.0 + epsilon // Nudge it away from 1.0
			}

			let numerator = log(safeValue)
			let denominator = log(safeBase)

			if abs(denominator) < epsilon {
				resultVector[i] = 0.0
			} else {
				resultVector[i] = numerator / denominator
			}
		}

		return resultVector
	}
}

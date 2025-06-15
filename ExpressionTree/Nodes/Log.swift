//
//  Log.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import simd

public class Log: CachedNode {
	public static var name: String {
		return "log"
	}

	public var children: [any Node]

	required public init(_ children: [any Node]) {
		assert(children.count == 2)
		self.children = children
	}

	public func _evaluate(using evaluator: Evaluator) -> any ExpressionResult {
		assert(children.count == 2)
		return LogResult(children.map { $0.evaluate(using: evaluator) })
	}

	public func debugValues(using evaluator: Evaluator, at coord: Coordinate) -> [String: String] {
		let vals = children.map { $0.evaluate(using: evaluator) }
		let inputValue = vals[0].value(at: coord)
		let inputBase = vals[1].value(at: coord)

		var debugVals = [String: String]()

		let numerator = log(abs(inputValue))
		let denominator = log(abs(inputBase))

		let result = numerator / denominator

		debugVals["coords"] = "\(coord.toDebugString())"
		debugVals["inputValue"] = "\(inputValue.toDebugString())"
		debugVals["inputBase"] = "\(inputBase.toDebugString())"
		debugVals["numerator"] = "\(numerator.toDebugString())"
		debugVals["denominator"] = "\(denominator.toDebugString())"
		debugVals["result"] = "\(result.toDebugString())"

		return debugVals
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
		let inputValue = e0.value(at: coord)
		let inputBase = e1.value(at: coord)

		var resultVector = Value.zero

		for i in 0..<3 {
			let numerator = log(abs(inputValue[i]))
			let denominator = log(abs(inputBase[i]))

			resultVector[i] = numerator / denominator

			if resultVector[i].isNaN {
				resultVector[i] = 0
			} else if resultVector[i].isInfinite {
				resultVector[i] = 1000
			}
		}

		return resultVector
	}
}

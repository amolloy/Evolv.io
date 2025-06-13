//
//  Operator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

public protocol Node: Identifiable {
	static var name: String { get }
	var children: [any Node] { get }

	init(_ children: [any Node]) throws
	
	func evaluate(using evaluator: Evaluator) -> any ExpressionResult
	func toString() -> String
}

public extension Node {
	func toString() -> String {
		let hasChildren = children.count > 0

		var str = ""
		if hasChildren {
			str += "("
		}

		str += "\(Self.name)"
		if hasChildren {
			let childStrings = children.map { $0.toString() }
			str += " \(childStrings.joined(separator: " "))"
			str += ")"
		}

		return str
	}
}

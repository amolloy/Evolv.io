//
//  MultiChildNode.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

open class MultiChildNode: Node {
	private var _children: [Node]
	public var children: [Node] { _children }

	public init(children: [Node]) {
		self._children = children
	}

	public convenience init(@NodeBuilder content: () -> [Node]) {
		let children = content()
		self.init(children: children)
	}

	public var name: String { fatalError("Subclass must override") }
	public func evaluate(width: Int, height: Int) -> ExpressionResult {
		fatalError("Subclass must override")
	}
}

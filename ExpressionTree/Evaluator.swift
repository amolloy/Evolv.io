//
//  Evaluator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import CoreGraphics

public struct EvaluationContext {
	let size: CGSize
}

public final class Evaluator {
    private var cache: [ObjectIdentifier: any ExpressionResult] = [:]
    // Nodes built synthetically inside another node's _evaluate (e.g.
    // GradientDirection's `PreventZero([children[1], Constant(-0.5)])`) have
    // no other owner -- nothing keeps them alive past the `evaluate(using:)`
    // call that caches their result. Swift can (and, confirmed while working
    // on the Metal codegen migration's parity tests, does) reuse a
    // just-deallocated object's memory address for the very next allocation,
    // which gives the new object the same ObjectIdentifier and makes it
    // collide with the old one's cache entry -- e.g. grad-direction's second
    // PreventZero (dirY) silently returning its first PreventZero's (dirX's)
    // cached result instead of computing its own. Retaining every cached
    // node for the evaluator's lifetime keeps its address from being
    // recycled during this evaluator's evaluation pass.
    private var retainedNodes: [any Node] = []

    private let context: EvaluationContext

	public var size: CGSize { get { context.size } }
	public func pixelToDotSize(_ s: Int) -> ComponentType {
		return ComponentType(s) / context.size.width
	}

	public init(size: CGSize) {
		self.context = EvaluationContext(size: size)
    }
    
	public func evaluate(node: any Node) -> any ExpressionResult {
        return node.evaluate(using: self)
    }

	internal func result(for node: any Node) -> (any ExpressionResult)? {
        let classNode = node as AnyObject
        return cache[ObjectIdentifier(classNode)]
    }

	internal func setResult(_ result: any ExpressionResult, for node: any Node) {
		let classNode = node as AnyObject
		retainedNodes.append(node)
        cache[ObjectIdentifier(classNode)] = result
    }
    
    fileprivate func getContext() -> EvaluationContext {
        return self.context
    }
}

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

    private let context: EvaluationContext

	public var size: CGSize { get { context.size } }

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
        cache[ObjectIdentifier(classNode)] = result
    }
    
    fileprivate func getContext() -> EvaluationContext {
        return self.context
    }
}

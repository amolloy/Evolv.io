//
//  Evaluator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

public struct EvaluationContext {
	let width: Int
	let height: Int
}

public final class Evaluator {
    private var cache: [ObjectIdentifier: any ExpressionResult] = [:]

    private let context: EvaluationContext

	internal var width: Int { get { context.width } }
	internal var height: Int { get { context.height } }

    public init(width: Int, height: Int) {
        self.context = EvaluationContext(width: width, height: height)
    }
    
    public func evaluate(root: Node) -> any ExpressionResult {
        return root.evaluate(using: self)
    }

    internal func result(for node: Node) -> (any ExpressionResult)? {
        let classNode = node as AnyObject
        return cache[ObjectIdentifier(classNode)]
    }

	internal func setResult(_ result: any ExpressionResult, for node: Node) {
		let classNode = node as AnyObject
        cache[ObjectIdentifier(classNode)] = result
    }
    
    fileprivate func getContext() -> EvaluationContext {
        return self.context
    }
}

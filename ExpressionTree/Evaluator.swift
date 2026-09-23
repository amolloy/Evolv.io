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
    private let context: EvaluationContext

	public var size: CGSize { get { context.size } }

	public init(size: CGSize) {
		self.context = EvaluationContext(size: size)
    }

	/// Renders `node` over this evaluator's full `size`, via the shared
	/// Metal pipeline cache (`MetalRenderContext`) -- this is what
	/// `NodeRenderer` calls to produce its pixel data.
	public func render(node: any Node, scale: ComponentType, supersample: Int) throws -> [Value] {
		try MetalRenderContext.shared.render(node: node,
											  width: Int(context.size.width),
											  height: Int(context.size.height),
											  scale: scale,
											  supersample: supersample)
	}
}

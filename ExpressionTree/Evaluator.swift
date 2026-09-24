//
//  Evaluator.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import CoreGraphics
import Metal

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
	/// `NodeRenderer` calls to produce its pixel data. `liveDebugValues`
	/// passes straight through to `MetalRenderContext.render` -- see its
	/// doc comment.
	public func render(node: any Node, scale: ComponentType, supersample: Int, liveDebugValues: MTLBuffer? = nil) throws -> [Value] {
		try MetalRenderContext.shared.render(node: node,
											  width: Int(context.size.width),
											  height: Int(context.size.height),
											  scale: scale,
											  supersample: supersample,
											  liveDebugValues: liveDebugValues)
	}

	/// The `MTLDevice` behind the shared render pipeline -- exposed so app-
	/// target code (e.g. `LiveDebugValues`) can allocate its own buffers
	/// against the same device `render(...)` ultimately submits work to.
	public var device: MTLDevice { MetalRenderContext.shared.device }

	/// What live `debug` controls (if any) `node`'s tree declares -- see
	/// `MetalRenderContext.debugControls(for:)`. `NodeRenderer` calls this
	/// after a render to build a `LiveDebugValues` for `NodeDebuggingView`.
	public func debugControls(for node: any Node) throws -> [DebugControlSlot] {
		try MetalRenderContext.shared.debugControls(for: node)
	}
}

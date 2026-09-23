//
//  MSLTreeEvaluator.swift
//  Evolv.io
//
//  Compiles a Node tree to MSL and evaluates it at an explicit list of
//  coordinates via a Metal compute dispatch. This is the engine the parity
//  test suite uses to check generated MSL against the existing Swift
//  `value(at:)` path (see the Metal codegen migration plan), and the first
//  piece of what becomes the production per-pixel render path once codegen
//  covers every node type.
//

import Metal

public enum MSLTreeEvaluatorError: Error, LocalizedError {
	case deviceUnavailable
	case functionNotFound
	case bufferAllocationFailed

	public var errorDescription: String? {
		switch self {
			case .deviceUnavailable: return "No Metal device/command queue available on this machine."
			case .functionNotFound: return "evaluateAtCoords function not found after compiling the library."
			case .bufferAllocationFailed: return "Failed to allocate a Metal buffer."
		}
	}
}

public final class MSLTreeEvaluator {
	private let device: MTLDevice
	private let queue: MTLCommandQueue

	public init() throws {
		guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
			throw MSLTreeEvaluatorError.deviceUnavailable
		}
		self.device = device
		self.queue = queue
	}

	/// Compiles `node`'s generated MSL fresh and evaluates it at every
	/// coordinate in `coords`, in one dispatch. No pipeline caching here --
	/// that's a production-render-path concern (see the plan's Evaluator
	/// section), not needed for one-off parity checks.
	/// Exposed for debugging generated MSL by hand (e.g. when a parity test
	/// fails and static reading of the codegen isn't enough) -- not used by
	/// the render path itself.
	public static func generateSource(for node: any Node) -> String {
		let context = MSLCodegenContext()
		let result = node.codegenMSL(into: context)
		return kernelSource(body: context.body(), resultVariable: result.variableName, functions: context.allFunctions(), resourceRequirements: context.resourceRequirements)
	}

	public func evaluate(node: any Node, at coords: [Coordinate]) throws -> [Value] {
		let context = MSLCodegenContext()
		let result = node.codegenMSL(into: context)

		let source = Self.kernelSource(body: context.body(), resultVariable: result.variableName, functions: context.allFunctions(), resourceRequirements: context.resourceRequirements)
		let compileOptions = MTLCompileOptions()
			// Default compile options use approximate ("fast math") instructions
			// for things like division/normalize. This evaluator only exists for
			// parity testing (not the eventual render path), where matching the
			// CPU's IEEE-compliant float64 math as closely as possible matters
			// more than the speed fast-math buys -- .safe forces IEEE-compliant
			// float32 math instead.
			compileOptions.mathMode = .safe
			let library = try device.makeLibrary(source: source, options: compileOptions)
		guard let function = library.makeFunction(name: "evaluateAtCoords") else {
			throw MSLTreeEvaluatorError.functionNotFound
		}
		let pipeline = try device.makeComputePipelineState(function: function)

		let count = coords.count
		guard count > 0,
			  let coordBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
			  let resultBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
			throw MSLTreeEvaluatorError.bufferAllocationFailed
		}

		let coordPtr = coordBuffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
		for i in 0..<count {
			coordPtr[i] = SIMD2<Float>(Float(coords[i].x), Float(coords[i].y))
		}

		guard let commandBuffer = queue.makeCommandBuffer(),
			  let encoder = commandBuffer.makeComputeCommandEncoder() else {
			throw MSLTreeEvaluatorError.bufferAllocationFailed
		}
		encoder.setComputePipelineState(pipeline)
		encoder.setBuffer(coordBuffer, offset: 0, index: 0)
		encoder.setBuffer(resultBuffer, offset: 0, index: 1)

		let threadgroupWidth = min(pipeline.maxTotalThreadsPerThreadgroup, count)
		encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
								 threadsPerThreadgroup: MTLSize(width: threadgroupWidth, height: 1, depth: 1))
		encoder.endEncoding()
		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()

		let resultPtr = resultBuffer.contents().bindMemory(to: Float.self, capacity: count * 4)
		var values = [Value](repeating: .zero, count: count)
		for i in 0..<count {
			let base = i * 4
			values[i] = Value(ComponentType(resultPtr[base]), ComponentType(resultPtr[base + 1]), ComponentType(resultPtr[base + 2]))
		}
		return values
	}

	private static func kernelSource(body: String, resultVariable: String, functions: String, resourceRequirements: MSLResourceRequirements) -> String {
		let preamble = mslSharedPreamble(functions: functions, resourceRequirements: resourceRequirements)

		return """
		#include <metal_stdlib>
		using namespace metal;

		\(preamble)inline float3 evalTree(float2 coord) {
			\(body)
			return \(resultVariable);
		}

		kernel void evaluateAtCoords(device const float2* coords [[buffer(0)]],
									  device float4* results [[buffer(1)]],
									  uint gid [[thread_position_in_grid]]) {
			results[gid] = float4(evalTree(coords[gid]), 1.0);
		}
		"""
	}
}

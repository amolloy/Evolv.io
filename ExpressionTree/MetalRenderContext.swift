//
//  MetalRenderContext.swift
//  Evolv.io
//
//  The production Metal rendering path: a process-wide shared device,
//  command queue, and compiled-pipeline cache, plus the full-image render
//  kernel (coordinate mapping, supersampling, sanitize) generalized from
//  the Figure9MetalBenchmark spike to run arbitrary codegen'd trees instead
//  of one hand-written kernel. `Evaluator.render(node:scale:supersample:)`
//  is the entry point callers use; this type is the machinery behind it.
//

import Metal

enum MetalRenderError: Error, LocalizedError {
	case functionNotFound
	case bufferAllocationFailed

	var errorDescription: String? {
		switch self {
			case .functionNotFound: return "renderImage function not found after compiling the library."
			case .bufferAllocationFailed: return "Failed to allocate a Metal buffer."
		}
	}
}

private struct RenderParams {
	var width: UInt32
	var height: UInt32
	var scale: Float
	var supersample: UInt32
}

/// Shared across every `Evaluator` instance (and so every `NodeRenderer`) in
/// the process -- deliberately not per-instance, since re-rendering the same
/// tree from a *different* NodeRenderer (e.g. ColorGradientDebugView builds
/// a fresh one on every slider change) should still hit the pipeline cache.
/// Access to the cache is locked since multiple NodeRenderers can render
/// concurrently (e.g. TreeVisualizerView's per-node thumbnails).
final class MetalRenderContext {
	static let shared = MetalRenderContext()

	let device: MTLDevice
	let commandQueue: MTLCommandQueue

	private var pipelineCache: [String: MTLComputePipelineState] = [:]
	private let lock = NSLock()

	private init() {
		// Every platform this app targets (macOS/iOS/visionOS on Apple
		// hardware from the last decade-plus) has Metal; a nil device here
		// would mean running in an environment this app was never designed
		// for. Consistent with the rest of this Metal-only render path
		// (there is no CPU fallback to degrade to), this is unrecoverable.
		guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else {
			fatalError("Metal is not available on this device")
		}
		self.device = device
		self.commandQueue = commandQueue
	}

	/// Compiles (or returns the cached pipeline for) `node`'s generated MSL.
	/// Keyed by `node.toString()` plus ColorGradient's live debug statics --
	/// those are baked into generated MSL as literals (not live uniforms; see
	/// ColorGradient._emitMSL), so a ColorGradientDebugView slider tick changes
	/// what a *structurally identical* tree should compile to. Without the
	/// statics in the key, a slider drag would silently serve a stale pipeline
	/// compiled with the old values -- wrong output, not just a missed cache
	/// optimization. Promoting these to real uniforms (so the cache key can
	/// go back to just the tree shape and a slider drag never recompiles) is
	/// deferred follow-up work, not required for correctness.
	func pipeline(for node: any Node) throws -> MTLComputePipelineState {
		let key = "\(node.toString())|\(ColorGradient.debugDelta)|\(ColorGradient.debugHeightFactor)|\(ColorGradient.debugLightZ)|\(ColorGradient.debugTapCount)"

		lock.lock()
		if let cached = pipelineCache[key] {
			lock.unlock()
			return cached
		}
		lock.unlock()

		let context = MSLCodegenContext()
		let result = node.codegenMSL(into: context)
		let source = Self.kernelSource(body: context.body(), resultVariable: result.variableName, functions: context.allFunctions(), resourceRequirements: context.resourceRequirements)

		let library = try device.makeLibrary(source: source, options: nil)
		guard let function = library.makeFunction(name: "renderImage") else {
			throw MetalRenderError.functionNotFound
		}
		let pipeline = try device.makeComputePipelineState(function: function)

		lock.lock()
		pipelineCache[key] = pipeline
		lock.unlock()
		return pipeline
	}

	/// Renders `node` over `width`x`height` pixels, matching
	/// `NodeRenderer.renderPixels`'s coordinate mapping and supersampling
	/// exactly (this replaces that CPU implementation, not just resembles it).
	func render(node: any Node, width: Int, height: Int, scale: ComponentType, supersample: Int) throws -> [Value] {
		let pipeline = try pipeline(for: node)
		let pixelCount = width * height

		guard let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
			throw MetalRenderError.bufferAllocationFailed
		}
		var params = RenderParams(width: UInt32(width), height: UInt32(height), scale: Float(scale), supersample: UInt32(supersample))
		guard let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<RenderParams>.stride, options: .storageModeShared) else {
			throw MetalRenderError.bufferAllocationFailed
		}

		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let encoder = commandBuffer.makeComputeCommandEncoder() else {
			throw MetalRenderError.bufferAllocationFailed
		}
		encoder.setComputePipelineState(pipeline)
		encoder.setBuffer(outputBuffer, offset: 0, index: 0)
		encoder.setBuffer(paramsBuffer, offset: 0, index: 1)

		let tgWidth = pipeline.threadExecutionWidth
		let tgHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / tgWidth)
		encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
								 threadsPerThreadgroup: MTLSize(width: tgWidth, height: tgHeight, depth: 1))
		encoder.endEncoding()
		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()

		let ptr = outputBuffer.contents().bindMemory(to: Float.self, capacity: pixelCount * 4)
		var data = [Value](repeating: .zero, count: pixelCount)
		for i in 0..<pixelCount {
			let base = i * 4
			data[i] = Value(ComponentType(ptr[base]), ComponentType(ptr[base + 1]), ComponentType(ptr[base + 2]))
		}
		return data
	}

	private static func kernelSource(body: String, resultVariable: String, functions: String, resourceRequirements: MSLResourceRequirements) -> String {
		let preamble = mslSharedPreamble(functions: functions, resourceRequirements: resourceRequirements)

		return """
		#include <metal_stdlib>
		using namespace metal;

		struct Params {
			uint width;
			uint height;
			float scale;
			uint supersample;
		};

		\(preamble)\(mslSanitizeFunction())

		inline float3 evalTree(float2 coord) {
			\(body)
			return \(resultVariable);
		}

		kernel void renderImage(device float4* outBuffer [[buffer(0)]],
								 constant Params& params [[buffer(1)]],
								 uint2 gid [[thread_position_in_grid]]) {
			if (gid.x >= params.width || gid.y >= params.height) return;

			float widthF = float(params.width);
			float heightF = float(params.height);
			float scaleFactor = 2.0 * params.scale;
			float scaleOffset = scaleFactor / 2.0;
			float dx = scaleFactor / widthF;
			float dy = scaleFactor / heightF;
			uint supersample = params.supersample;

			float yc = (float(int(params.height) - 1 - int(gid.y)) + 0.5) / heightF * scaleFactor - scaleOffset;
			float xc = (float(gid.x) + 0.5) / widthF * scaleFactor - scaleOffset;

			float3 accumulated = float3(0.0);
			for (uint sy = 0; sy < supersample; sy++) {
				float subYc = yc + (float(sy) + 0.5) / float(supersample) * dy - dy * 0.5;
				for (uint sx = 0; sx < supersample; sx++) {
					float subXc = xc + (float(sx) + 0.5) / float(supersample) * dx - dx * 0.5;
					accumulated += sanitize(evalTree(float2(subXc, subYc)));
				}
			}
			float3 pixel = accumulated / float(supersample * supersample);

			uint idx = gid.y * params.width + gid.x;
			outBuffer[idx] = float4(pixel, 1.0);
		}
		"""
	}
}

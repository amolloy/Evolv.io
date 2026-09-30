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

import CoreGraphics
import Metal

public enum MetalRenderError: Error, LocalizedError {
	case functionNotFound
	case bufferAllocationFailed
	/// The GPU stopped (or never ran) the band covering `rows` -- most often
	/// macOS killing a command buffer that ran too long. Rows before
	/// `rows.lowerBound` rendered; the rest of the image didn't.
	case gpuFailed(rows: Range<Int>, height: Int, reason: String)
	/// The GPU stopped (or never ran) a pass filling a grid cache -- see
	/// `MetalRenderContext.fillSampleCaches`.
	case sampleCacheFailed(reason: String)

	public var errorDescription: String? {
		switch self {
			case .functionNotFound: return "renderImage function not found after compiling the library."
			case .bufferAllocationFailed: return "Failed to allocate a Metal buffer."
			case .gpuFailed(let rows, let height, let reason):
				return "The GPU stopped rendering at rows \(rows.lowerBound)-\(rows.upperBound - 1) of \(height): \(reason)"
			case .sampleCacheFailed(let reason):
				return "The GPU stopped while filling a grid cache: \(reason)"
		}
	}
}

private struct RenderParams {
	var width: UInt32
	var height: UInt32
	var supersample: UInt32
	/// First image row of the band being dispatched -- see `render`.
	var rowOffset: UInt32
	/// The supersamples this pass adds, in row-major order over the
	/// supersample x supersample grid -- see `render`.
	var sampleStart: UInt32
	var sampleCount: UInt32
	var padding: SIMD2<UInt32> = .zero
	/// (xMin, yMin, xSpan, ySpan) of the coordinate rectangle the image
	/// covers -- `scale: s` is just the centered square (-s, -s, 2s, 2s).
	var bounds: SIMD4<Float>
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

	private struct CompiledTree {
		let pipeline: MTLComputePipelineState
		let debugControls: [DebugControlSlot]
		/// `fn grid(...)` children rendered into textures before the main
		/// pass, in fill order -- see `fillSampleCaches`.
		let sampleCaches: [SampleCache]
		/// Writes each cache's grid spacing into a buffer; nil without caches.
		let measurePipeline: MTLComputePipelineState?
		/// One per cache, same order.
		let fillPipelines: [MTLComputePipelineState]
	}
	private var pipelineCache: [String: CompiledTree] = [:]
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

	/// Called by `NodeRegistry.reload()`: a DSL node's `toString()` doesn't
	/// encode the *content* of whatever module its `requires()` resolved
	/// to, so editing a module file and reloading could otherwise still
	/// serve a pipeline compiled against the old file's MSL text under an
	/// identical cache key. Clearing the whole cache on every reload is
	/// coarser than re-keying on module content, but reload is a rare,
	/// explicit user action (not a per-frame cost), so simple correctness
	/// wins over precision here.
	func clearPipelineCache() {
		lock.lock()
		pipelineCache.removeAll()
		lock.unlock()
	}

	/// Compiles (or returns the cached compile for) `node`'s generated MSL,
	/// alongside the manifest of any live-tunable `debug` controls its
	/// `.evolvnode` params registered (see `DebugControlSlot`). Keyed by
	/// `node.toString()` alone -- every node's *non-live* tunables are baked
	/// into `.evolvnode` text now (see color-grad-curvature.evolvnode etc.),
	/// and any edit there goes through NodeRegistry.reload(), which clears
	/// this whole cache directly, so there's no live-mutable Swift state
	/// left that could make an identical `toString()` compile to different
	/// MSL.
	/// `sampleCaching: false` (tests only) calls every `fn grid(...)` child
	/// directly instead of through a texture, and is cached separately.
	private func compiled(for node: any Node, sampleCaching: Bool = true) throws -> CompiledTree {
		let key = (sampleCaching ? "" : "nocache:") + node.toString()

		lock.lock()
		if let cached = pipelineCache[key] {
			lock.unlock()
			return cached
		}
		lock.unlock()

		let context = MSLCodegenContext(sampleCaching: sampleCaching)
		let result = node.codegenMSL(into: context)
		let caches = context.sampleCaches
		let source = Self.kernelSource(body: context.body(), resultVariable: result.variableName, functions: context.allFunctions(), resourceRequirements: context.resourceRequirements, customModules: context.customModulesMSL(), sampleCaches: caches)

		let library = try device.makeLibrary(source: source, options: nil)
		func pipeline(named name: String) throws -> MTLComputePipelineState {
			guard let function = library.makeFunction(name: name) else {
				throw MetalRenderError.functionNotFound
			}
			return try device.makeComputePipelineState(function: function)
		}
		let compiledTree = CompiledTree(pipeline: try pipeline(named: "renderImage"),
										debugControls: context.debugControls,
										sampleCaches: caches,
										measurePipeline: caches.isEmpty ? nil : try pipeline(named: "measureSampleCaches"),
										fillPipelines: try caches.map { try pipeline(named: "fillSampleCache\($0.index)") })

		lock.lock()
		pipelineCache[key] = compiledTree
		lock.unlock()
		return compiledTree
	}

	/// What live `debug` controls (if any) `node`'s tree declares -- reuses
	/// whatever's already cached by `compiled(for:)` (a render call, or a
	/// prior call to this method), so asking is effectively free once a
	/// tree has been compiled once. `NodeRenderer` calls this after its
	/// first render to build a `LiveDebugValues` for `NodeDebuggingView`.
	func debugControls(for node: any Node) throws -> [DebugControlSlot] {
		try compiled(for: node).debugControls
	}

	/// Renders `node` over `width`x`height` pixels, matching
	/// `NodeRenderer.renderPixels`'s coordinate mapping and supersampling
	/// exactly (this replaces that CPU implementation, not just resembles it).
	/// `liveDebugValues`, when supplied, is bound as the kernel's
	/// `debugValues` buffer as-is (this is the actual "live, no recompile"
	/// mechanism -- see `LiveDebugValues`); `nil` (every call site except
	/// `NodeDebuggingView`'s) builds a fresh buffer from each control's
	/// default instead, so a tree with debug controls still renders
	/// correctly wherever nobody's watching sliders (the main canvas,
	/// thumbnails, etc).
	func render(node: any Node, width: Int, height: Int, scale: ComponentType, supersample: Int, liveDebugValues: MTLBuffer? = nil) throws -> [Value] {
		try render(node: node, width: width, height: height,
				   bounds: CGRect(x: -scale, y: -scale, width: 2 * scale, height: 2 * scale),
				   supersample: supersample, liveDebugValues: liveDebugValues)
	}

	/// Same as `render(node:width:height:scale:...)`, but over an arbitrary
	/// coordinate rectangle -- `bounds.minX...maxX` across, `minY...maxY` from
	/// bottom to top -- instead of the centered `[-scale, scale]` square.
	/// Used by the MCP `render` tool to match a reference figure's framing.
	///
	/// The work is split into many small command buffers, so no single GPU
	/// job runs long enough for macOS to kill it. Figure 13's tree at
	/// 800x800 with 4x4 supersampling is about 30 s of GPU time; as one
	/// command buffer it was cut off partway (the rest of the image stayed
	/// black). Splitting only by rows wasn't enough: each thread still
	/// evaluated the tree 16 times in a row, about 0.4 s, and even a one-row
	/// band tripped the GPU hang detector. So each pass covers a band of
	/// rows *and* a run of each pixel's supersamples, accumulating into the
	/// output buffer; the last pass for a band divides. After every pass,
	/// the band height and samples per pass are resized from its measured
	/// GPU time to take about `targetPassSeconds` (growing at most 4x at a
	/// time). Every pass is checked, and a failed one throws
	/// `MetalRenderError.gpuFailed` instead of returning a partly black
	/// image. The samples are added in the same order with the same
	/// coordinates as a single pass, so the output is identical.
	/// `fixedBandRows`/`fixedSamplesPerPass` (tests only) turn the
	/// adapting off.
	///
	/// A tree with `fn grid(...)` children (blur's source) first renders each
	/// of them into a texture covering the image -- see `fillSampleCaches`.
	/// `sampleCaching: false` (tests only) skips that and calls them directly.
	func render(node: any Node, width: Int, height: Int, bounds: CGRect, supersample: Int, liveDebugValues: MTLBuffer? = nil,
				fixedBandRows: Int? = nil, fixedSamplesPerPass: Int? = nil, sampleCaching: Bool = true) throws -> [Value] {
		let compiledTree = try compiled(for: node, sampleCaching: sampleCaching)
		let pipeline = compiledTree.pipeline
		let pixelCount = width * height

		guard let outputBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
			throw MetalRenderError.bufferAllocationFailed
		}
		var params = RenderParams(width: UInt32(width), height: UInt32(height), supersample: UInt32(supersample),
								  rowOffset: 0, sampleStart: 0, sampleCount: 0,
								  bounds: SIMD4<Float>(Float(bounds.minX), Float(bounds.minY), Float(bounds.width), Float(bounds.height)))
		guard let debugValuesBuffer = liveDebugValues ?? mslMakeDefaultDebugValuesBuffer(device: device, controls: compiledTree.debugControls) else {
			throw MetalRenderError.bufferAllocationFailed
		}

		let caches = try fillSampleCaches(compiledTree, bounds: bounds, debugValues: debugValuesBuffer)

		let tgWidth = pipeline.threadExecutionWidth
		let tgHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / tgWidth)
		let totalSamples = supersample * supersample
		let adaptive = fixedBandRows == nil && fixedSamplesPerPass == nil
		// Start with enough threads to fill the GPU, one sample each.
		var bandRows = max(1, fixedBandRows ?? (Self.initialPassThreads + width - 1) / max(1, width))
		var samplesPerPass = max(1, fixedSamplesPerPass ?? 1)
		let minBandRows = max(1, (Self.minPassThreads + width - 1) / max(1, width))
		var row = 0
		while row < height {
			let rows = min(bandRows, height - row)
			var sample = 0
			while sample < totalSamples {
				let count = min(samplesPerPass, totalSamples - sample)
				params.rowOffset = UInt32(row)
				params.sampleStart = UInt32(sample)
				params.sampleCount = UInt32(count)

				guard let commandBuffer = commandQueue.makeCommandBuffer(),
					  let encoder = commandBuffer.makeComputeCommandEncoder() else {
					throw MetalRenderError.bufferAllocationFailed
				}
				encoder.setComputePipelineState(pipeline)
				encoder.setBuffer(outputBuffer, offset: 0, index: 0)
				encoder.setBytes(&params, length: MemoryLayout<RenderParams>.stride, index: 1)
				encoder.setBuffer(debugValuesBuffer, offset: 0, index: 2)
				caches?.bind(to: encoder, upTo: caches?.textures.count ?? 0)
				encoder.dispatchThreads(MTLSize(width: width, height: rows, depth: 1),
										 threadsPerThreadgroup: MTLSize(width: tgWidth, height: min(tgHeight, rows), depth: 1))
				encoder.endEncoding()
				commandBuffer.commit()
				commandBuffer.waitUntilCompleted()

				guard commandBuffer.status == .completed else {
					let reason = commandBuffer.error.map { "\($0.localizedDescription)" } ?? "command buffer status \(commandBuffer.status.rawValue)"
					print("MetalRenderContext: pass failed at rows \(row)..<\(row + rows), samples \(sample)..<\(sample + count) of \(totalSamples), image height \(height): \(reason)")
					throw MetalRenderError.gpuFailed(rows: row..<(row + rows), height: height, reason: reason)
				}
				sample += count

				guard adaptive else { continue }
				// Cost of one sample for one row; size the next passes so
				// rows x samples fits the target.
				let gpuSeconds = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
				let perSampleRow = gpuSeconds / Double(rows * count)
				let budget = perSampleRow > 0 ? Int(Self.targetPassSeconds / perSampleRow) : Int.max / 4
				if budget >= totalSamples * bandRows {
					samplesPerPass = min(totalSamples, samplesPerPass * 4)
					if samplesPerPass == totalSamples {
						bandRows = max(1, min(budget / totalSamples, bandRows * 4))
					}
				} else if budget >= bandRows {
					samplesPerPass = max(1, min(budget / bandRows, samplesPerPass * 4))
				} else {
					samplesPerPass = 1
					bandRows = max(minBandRows, budget)
				}
			}
			row += rows
		}

		let ptr = outputBuffer.contents().bindMemory(to: Float.self, capacity: pixelCount * 4)
		var data = [Value](repeating: .zero, count: pixelCount)
		for i in 0..<pixelCount {
			let base = i * 4
			data[i] = Value(ComponentType(ptr[base]), ComponentType(ptr[base + 1]), ComponentType(ptr[base + 2]))
		}
		return data
	}

	/// The textures `fillSampleCaches` rendered, and where each sits on its
	/// grid (the kernels' `cacheInfo`).
	private struct FilledSampleCaches {
		let textures: [MTLTexture]
		let info: MTLBuffer
		/// Bound in place of a cache that isn't filled (yet, or at all).
		let placeholder: MTLTexture

		/// Binds `cacheInfo` and caches `0..<count`; later ones get the
		/// placeholder, which a fill pass never reads (a cache's function
		/// only reads caches before it).
		func bind(to encoder: MTLComputeCommandEncoder, upTo count: Int) {
			encoder.setBuffer(info, offset: 0, index: 3)
			for (i, texture) in textures.enumerated() {
				encoder.setTexture(i < count ? texture : placeholder, index: i)
			}
		}
	}

	/// Renders each `fn grid(spacing)` child of the tree (blur's source) once
	/// per grid cell into a texture, so the main pass reads a texel instead
	/// of evaluating the child's whole subtree at every tap. Blur takes 1764
	/// taps per call, and Figure 13 calls it 4 times per sample, so this
	/// replaces about 7000 evaluations of its source per sample with one per
	/// cell.
	///
	/// A texture covers the image bounds plus a quarter of their size on
	/// each side, plus `sampleCacheMarginCells` cells, since a node samples
	/// around the point it's asked for (blur up to 10 cells out; an outer
	/// grad-direction a little further). A call outside that, or off the
	/// grid, evaluates the child directly, so the texture's extent only
	/// affects speed, never the image. A cache whose grid would need more
	/// than `maxSampleCacheSize` cells across isn't filled at all and every
	/// call goes direct. Caches fill in order, each in row bands sized like
	/// `render`'s passes, since a cache may read the ones before it.
	private func fillSampleCaches(_ compiledTree: CompiledTree, bounds: CGRect, debugValues: MTLBuffer) throws -> FilledSampleCaches? {
		let caches = compiledTree.sampleCaches
		guard !caches.isEmpty, let measurePipeline = compiledTree.measurePipeline else { return nil }

		// The spacings can depend on live debug values, so the GPU computes
		// them from the same expressions the kernels use.
		guard let spacingsBuffer = device.makeBuffer(length: caches.count * MemoryLayout<Float>.stride, options: .storageModeShared) else {
			throw MetalRenderError.bufferAllocationFailed
		}
		try runPass { encoder in
			encoder.setComputePipelineState(measurePipeline)
			encoder.setBuffer(spacingsBuffer, offset: 0, index: 0)
			encoder.setBuffer(debugValues, offset: 0, index: 2)
			encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
		}
		let spacings = spacingsBuffer.contents().bindMemory(to: Float.self, capacity: caches.count)

		let placeholderDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
		placeholderDescriptor.usage = [.shaderRead]
		guard let placeholder = device.makeTexture(descriptor: placeholderDescriptor) else {
			throw MetalRenderError.bufferAllocationFailed
		}

		var textures: [MTLTexture] = []
		var info: [SIMD4<Int32>] = []
		for cache in caches {
			guard let region = Self.sampleCacheRegion(spacing: Double(spacings[cache.index]), bounds: bounds) else {
				// A zero size makes every call go direct.
				textures.append(placeholder)
				info.append(.zero)
				continue
			}
			let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: Int(region.size.x), height: Int(region.size.y), mipmapped: false)
			descriptor.usage = [.shaderRead, .shaderWrite]
			descriptor.storageMode = .private
			guard let texture = device.makeTexture(descriptor: descriptor) else {
				throw MetalRenderError.bufferAllocationFailed
			}
			textures.append(texture)
			info.append(SIMD4(region.origin.x, region.origin.y, region.size.x, region.size.y))
		}
		guard let infoBuffer = device.makeBuffer(bytes: info, length: info.count * MemoryLayout<SIMD4<Int32>>.stride, options: .storageModeShared) else {
			throw MetalRenderError.bufferAllocationFailed
		}
		let filled = FilledSampleCaches(textures: textures, info: infoBuffer, placeholder: placeholder)

		for cache in caches where textures[cache.index] !== placeholder {
			let target = textures[cache.index]
			let fillPipeline = compiledTree.fillPipelines[cache.index]
			let width = target.width, height = target.height
			let tgWidth = fillPipeline.threadExecutionWidth
			let tgHeight = max(1, fillPipeline.maxTotalThreadsPerThreadgroup / tgWidth)
			var bandRows = max(1, (Self.initialPassThreads + width - 1) / width)
			let minBandRows = max(1, (Self.minPassThreads + width - 1) / width)
			var row = 0
			while row < height {
				let rows = min(bandRows, height - row)
				var rowOffset = UInt32(row)
				let gpuSeconds = try runPass { encoder in
					encoder.setComputePipelineState(fillPipeline)
					encoder.setBuffer(debugValues, offset: 0, index: 2)
					filled.bind(to: encoder, upTo: cache.index)
					encoder.setTexture(target, index: caches.count)
					encoder.setBytes(&rowOffset, length: MemoryLayout<UInt32>.stride, index: 4)
					encoder.dispatchThreads(MTLSize(width: width, height: rows, depth: 1),
											 threadsPerThreadgroup: MTLSize(width: tgWidth, height: min(tgHeight, rows), depth: 1))
				}
				row += rows
				let perRow = gpuSeconds / Double(rows)
				let budget = perRow > 0 ? Int(Self.targetPassSeconds / perRow) : Int.max / 4
				bandRows = max(minBandRows, min(budget, bandRows * 4))
			}
		}
		return filled
	}

	/// Where a cache with grid `spacing` goes for an image over `bounds`: the
	/// grid cell of its first texel and its size in cells, or nil if the
	/// spacing is unusable or the texture would be too big.
	private static func sampleCacheRegion(spacing: Double, bounds: CGRect) -> (origin: SIMD2<Int32>, size: SIMD2<Int32>)? {
		guard spacing.isFinite, spacing > 0 else { return nil }
		func axis(_ lo: Double, _ hi: Double) -> (first: Int32, count: Int32)? {
			let pad = (hi - lo) * 0.25
			// Cell i's centre is (i + 0.5) * spacing.
			let first = ((lo - pad) / spacing - 0.5).rounded(.down) - Double(sampleCacheMarginCells)
			let last = ((hi + pad) / spacing - 0.5).rounded(.up) + Double(sampleCacheMarginCells)
			let count = last - first + 1
			guard first.isFinite, count.isFinite, count <= Double(maxSampleCacheSize), Swift.abs(first) < Double(Int32.max / 2) else { return nil }
			return (Int32(first), Int32(count))
		}
		guard let x = axis(Double(bounds.minX), Double(bounds.maxX)), let y = axis(Double(bounds.minY), Double(bounds.maxY)) else { return nil }
		return (SIMD2(x.first, y.first), SIMD2(x.count, y.count))
	}

	/// Cells beyond the padded image bounds a grid cache still covers.
	private static let sampleCacheMarginCells = 24
	/// The most cells a grid cache may have along either axis (4096 x 4096
	/// float4 texels is 256 MB).
	private static let maxSampleCacheSize = 4096

	/// Encodes one pass with `encode`, runs it, and returns its GPU time.
	@discardableResult
	private func runPass(_ encode: (MTLComputeCommandEncoder) -> Void) throws -> Double {
		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let encoder = commandBuffer.makeComputeCommandEncoder() else {
			throw MetalRenderError.bufferAllocationFailed
		}
		encode(encoder)
		encoder.endEncoding()
		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()
		guard commandBuffer.status == .completed else {
			let reason = commandBuffer.error.map { "\($0.localizedDescription)" } ?? "command buffer status \(commandBuffer.status.rawValue)"
			print("MetalRenderContext: grid cache pass failed: \(reason)")
			throw MetalRenderError.sampleCacheFailed(reason: reason)
		}
		return commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
	}

	/// Pixels in the first pass of a render (one sample each). One sample
	/// of Figure 13's tree takes a GPU thread about 20 ms on an M1 Max, and
	/// this many take about 25 ms together.
	private static let initialPassThreads = 4_096
	/// What later passes are sized to take, from the previous pass's GPU
	/// time. While the app's window is in front, macOS kills GPU work that
	/// holds the GPU long enough to delay the display ("Impacting
	/// Interactivity"), and after a few such errors it ignores the
	/// process's GPU work altogether, so passes stay about two frames
	/// long. Figure 13 at 800x800 takes about 3 s this way instead of 2.
	private static let targetPassSeconds = 0.03
	/// Passes never shrink below this many threads (whole rows), so the
	/// GPU isn't left mostly idle.
	private static let minPassThreads = 1_024

	private static func kernelSource(body: String, resultVariable: String, functions: String, resourceRequirements: MSLResourceRequirements, customModules: String, sampleCaches: [SampleCache]) -> String {
		let preamble = mslSharedPreamble(functions: functions, resourceRequirements: resourceRequirements, customModules: customModules, sampleCaches: sampleCaches)

		return """
		#include <metal_stdlib>
		using namespace metal;

		struct Params {
			uint width;
			uint height;
			uint supersample;
			uint rowOffset; // first image row of this band
			uint sampleStart; // first supersample this pass adds
			uint sampleCount; // how many supersamples this pass adds
			uint2 padding;
			float4 bounds; // xMin, yMin, xSpan, ySpan
		};

		\(preamble)\(mslSanitizeFunction())

		inline float3 evalTree(float2 coord, constant float* debugValues EVOLV_CACHE_PARAMS) {
			\(body)
			return \(resultVariable);
		}

		kernel void renderImage(device float4* outBuffer [[buffer(0)]],
								 constant Params& params [[buffer(1)]],
								 constant float* debugValues [[buffer(2)]]
								 EVOLV_CACHE_KERNEL_PARAMS,
								 uint2 bandGid [[thread_position_in_grid]]) {
			uint2 gid = uint2(bandGid.x, bandGid.y + params.rowOffset);
			if (gid.x >= params.width || gid.y >= params.height) return;

			float widthF = float(params.width);
			float heightF = float(params.height);
			float xSpan = params.bounds.z;
			float ySpan = params.bounds.w;
			float dx = xSpan / widthF;
			float dy = ySpan / heightF;
			uint supersample = params.supersample;

			float yc = (float(int(params.height) - 1 - int(gid.y)) + 0.5) / heightF * ySpan + params.bounds.y;
			float xc = (float(gid.x) + 0.5) / widthF * xSpan + params.bounds.x;

			// Samples run row-major over the supersample grid; this pass adds
			// sampleStart..<sampleStart + sampleCount to what earlier passes
			// left in outBuffer, and the pass that adds the last one divides.
			uint idx = gid.y * params.width + gid.x;
			uint totalSamples = supersample * supersample;
			uint end = min(params.sampleStart + params.sampleCount, totalSamples);
			float3 accumulated = (params.sampleStart == 0) ? float3(0.0) : outBuffer[idx].xyz;
			for (uint s = params.sampleStart; s < end; s++) {
				uint sy = s / supersample;
				uint sx = s % supersample;
				float subYc = yc + (float(sy) + 0.5) / float(supersample) * dy - dy * 0.5;
				float subXc = xc + (float(sx) + 0.5) / float(supersample) * dx - dx * 0.5;
				accumulated += sanitize(evalTree(float2(subXc, subYc), debugValues EVOLV_CACHE_ARGS));
			}
			float3 pixel = (end == totalSamples) ? accumulated / float(totalSamples) : accumulated;
			outBuffer[idx] = float4(pixel, 1.0);
		}

		\(sampleCacheKernels(sampleCaches))
		"""
	}

	/// `measureSampleCaches` writes every cache's grid spacing into buffer 0;
	/// `fillSampleCache<i>` evaluates cache i's function at the centre of
	/// every cell of its texture (bound at texture index `caches.count`),
	/// for the band of rows starting at the row in buffer 4.
	private static func sampleCacheKernels(_ caches: [SampleCache]) -> String {
		guard !caches.isEmpty else { return "" }
		let spacings = caches.map { "spacings[\($0.index)] = \($0.spacingExpression);" }.joined(separator: "\n\t")
		let fills = caches.map { cache in
			"""
			kernel void fillSampleCache\(cache.index)(texture2d<float, access::write> target [[texture(\(caches.count))]],
											constant uint& rowOffset [[buffer(4)]],
											constant float* debugValues [[buffer(2)]]
											EVOLV_CACHE_KERNEL_PARAMS,
											uint2 bandGid [[thread_position_in_grid]]) {
				uint2 gid = uint2(bandGid.x, bandGid.y + rowOffset);
				if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;
				float spacing = \(cache.spacingExpression);
				float2 coord = (float2(int2(gid) + cacheInfo[\(cache.index)].origin) + 0.5) * spacing;
				target.write(float4(\(cache.functionName)(coord, debugValues EVOLV_CACHE_ARGS), 0.0), gid);
			}
			"""
		}.joined(separator: "\n\n")
		return """
		kernel void measureSampleCaches(device float* spacings [[buffer(0)]],
										constant float* debugValues [[buffer(2)]]) {
			\(spacings)
		}

		\(fills)
		"""
	}
}

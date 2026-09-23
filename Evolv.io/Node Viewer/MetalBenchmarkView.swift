//
//  MetalBenchmarkView.swift
//  Evolv.io
//
//  Feasibility-spike harness for the "port node trees to Metal" question:
//  hand-ports Figure 9 (the deepest tree we have, nested color-grad calls)
//  to a Metal compute kernel and times it against the existing CPU path,
//  so the compile-overhead / speedup questions can be answered with real
//  numbers instead of guessing. Not a general tree->MSL compiler -- see
//  the comment above `figure9MetalSource` for what's hand-baked in.
//

import SwiftUI
import Metal
import simd
import ExpressionTree

// MARK: - Hand-written Metal port of "Figure 9"
//
// source/p1/p2/color/p3 for both `color-grad` calls are baked in directly
// as MSL constants below, matching the literal values in
// `ContentView.sampleExpressions["Figure 9"]`. A real codegen backend would
// need to emit these as arbitrary sub-expressions instead of constants --
// this spike only needs to answer "is Metal fast enough to be worth that,"
// not build the general compiler yet.
//
// The constants also assume `ColorGradient.debugDelta/debugHeightFactor/
// debugLightZ/debugSharedNormal` are at the values noted below. `runBenchmark`
// checks the live statics against these and surfaces a warning if they've
// since drifted (e.g. from playing with ColorGradientDebugView), since a
// silent mismatch there would show up as a bogus CPU/GPU parity diff that
// has nothing to do with the port being wrong.
private let assumedDebugDelta: ComponentType = 0.01
private let assumedDebugHeightFactor: ComponentType = 20.0
private let assumedDebugLightZ: ComponentType = 0.0
private let assumedDebugSharedNormal = false

private let figure9MetalSource = """
#include <metal_stdlib>
using namespace metal;

constant float kDelta = 0.01;           // (|p1|/3.1) * debugDelta, p1=3.1 in every Figure 9 call
constant float kHeightFactorInner = 27.0; // p3(1.35) * debugHeightFactor(20)
constant float kHeightFactorOuter = 27.0; // p3(1.35) * debugHeightFactor(20)
constant float kLightZ = 0.0;             // p3 * debugLightZ(0)
constant float kAngleInner = 1.86;
constant float kAngleOuter = 1.9;
constant float3 kColorInner = float3(0.95, 0.7, 0.59);
constant float3 kColorOuter = float3(0.95, 0.7, 0.35);
constant float kP3 = 1.35;

inline float3 vround(float3 v0, float3 v1) {
    float3 q = rint(v0 / v1);
    return q * v1;
}

inline float3 vlogSafe(float3 v0, float3 v1) {
    float3 num = log(abs(v0));
    float3 den = log(abs(v1));
    float3 r = num / den;
    return select(float3(0.0), r, !isnan(r));
}

inline float3 sourceInner(float2 coord) {
    // round(y + log(invert(y), 15.5), x)
    float y = coord.y;
    float3 yv = float3(y);
    float3 invY = float3(1.0) - yv;
    float3 logTerm = vlogSafe(invY, float3(15.5));
    float3 sum = yv + logTerm;
    return vround(sum, float3(coord.x));
}

inline float3 colorGradShared(float2 coord,
                               float angle,
                               float heightFactor,
                               float3 colorTint,
                               float3 hXNegOuter, float3 hXNegInner, float3 hXPosInner, float3 hXPosOuter,
                               float3 hYNegOuter, float3 hYNegInner, float3 hYPosInner, float3 hYPosOuter) {
    float lightDx = cos(angle);
    float lightDy = sin(angle);
    float3 lightDir = float3(lightDx, lightDy, kLightZ);
    float lightLen = length(lightDir);
    bool lightValid = lightLen >= 1e-9;
    float3 lightN = lightValid ? lightDir / lightLen : float3(0.0);

    float3 base;
    for (int i = 0; i < 3; i++) {
        float gxInner = hXNegInner[i] - hXPosInner[i];
        float gxOuter = hXNegOuter[i] - hXPosOuter[i];
        float gx = 0.6 * gxInner + 0.4 * gxOuter;

        float gyInner = hYNegInner[i] - hYPosInner[i];
        float gyOuter = hYNegOuter[i] - hYPosOuter[i];
        float gy = 0.6 * gyInner + 0.4 * gyOuter;

        float3 normal = float3(-gx, -gy, 1.0 / heightFactor);
        float nLen = length(normal);
        if (!lightValid || nLen < 1e-9) {
            base[i] = 0.5;
            continue;
        }
        float3 normalN = normal / nLen;
        float t = dot(normalN, lightN);
        base[i] = colorTint[i] * t;
    }

    float3 result;
    for (int i = 0; i < 3; i++) {
        float signVal = base[i] < 0.0 ? -1.0 : 1.0;
        result[i] = signVal * pow(abs(base[i]), kP3);
    }
    return result;
}

inline float3 colorGradInner(float2 coord) {
    float dOuter = kDelta;
    float dInner = kDelta * 0.5;

    float3 hXNegOuter = sourceInner(coord - float2(dOuter, 0.0));
    float3 hXNegInner = sourceInner(coord - float2(dInner, 0.0));
    float3 hXPosInner = sourceInner(coord + float2(dInner, 0.0));
    float3 hXPosOuter = sourceInner(coord + float2(dOuter, 0.0));

    float3 hYNegOuter = sourceInner(coord - float2(0.0, dOuter));
    float3 hYNegInner = sourceInner(coord - float2(0.0, dInner));
    float3 hYPosInner = sourceInner(coord + float2(0.0, dInner));
    float3 hYPosOuter = sourceInner(coord + float2(0.0, dOuter));

    return colorGradShared(coord, kAngleInner, kHeightFactorInner, kColorInner,
                            hXNegOuter, hXNegInner, hXPosInner, hXPosOuter,
                            hYNegOuter, hYNegInner, hYPosInner, hYPosOuter);
}

inline float3 sourceOuter(float2 coord) {
    // round(abs(round(log(y + colorGradInner(coord), 0.19), x)) + log(invert(y), 15.5), x)
    float3 cg = colorGradInner(coord);
    float y = coord.y;
    float3 yv = float3(y);
    float3 a10 = yv + cg;
    float3 l9 = vlogSafe(a10, float3(0.19));
    float3 r8 = vround(l9, float3(coord.x));
    float3 abs7 = abs(r8);

    float3 invY = float3(1.0) - yv;
    float3 l17 = vlogSafe(invY, float3(15.5));

    float3 a6 = abs7 + l17;
    return vround(a6, float3(coord.x));
}

inline float3 colorGradOuter(float2 coord) {
    float dOuter = kDelta;
    float dInner = kDelta * 0.5;

    float3 hXNegOuter = sourceOuter(coord - float2(dOuter, 0.0));
    float3 hXNegInner = sourceOuter(coord - float2(dInner, 0.0));
    float3 hXPosInner = sourceOuter(coord + float2(dInner, 0.0));
    float3 hXPosOuter = sourceOuter(coord + float2(dOuter, 0.0));

    float3 hYNegOuter = sourceOuter(coord - float2(0.0, dOuter));
    float3 hYNegInner = sourceOuter(coord - float2(0.0, dInner));
    float3 hYPosInner = sourceOuter(coord + float2(0.0, dInner));
    float3 hYPosOuter = sourceOuter(coord + float2(0.0, dOuter));

    return colorGradShared(coord, kAngleOuter, kHeightFactorOuter, kColorOuter,
                            hXNegOuter, hXNegInner, hXPosInner, hXPosOuter,
                            hYNegOuter, hYNegInner, hYPosInner, hYPosOuter);
}

inline float3 figure9(float2 coord) {
    // round(log(y + colorGradOuter(coord), 0.19), x)
    float3 cg = colorGradOuter(coord);
    float y = coord.y;
    float3 a3 = float3(y) + cg;
    float3 l2 = vlogSafe(a3, float3(0.19));
    return vround(l2, float3(coord.x));
}

inline float3 sanitize(float3 v) {
    float3 r = v;
    for (int i = 0; i < 3; i++) {
        if (isnan(r[i])) r[i] = 0.0;
        else if (isinf(r[i])) r[i] = r[i] > 0.0 ? 1.0 : -1.0;
    }
    return r;
}

struct Params {
    uint width;
    uint height;
    float scale;
    uint supersample;
};

kernel void renderFigure9(device float4* outBuffer [[buffer(0)]],
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
            accumulated += sanitize(figure9(float2(subXc, subYc)));
        }
    }
    float3 pixel = accumulated / float(supersample * supersample);

    uint idx = gid.y * params.width + gid.x;
    outBuffer[idx] = float4(pixel, 1.0);
}
"""

private struct Figure9Params {
    var width: UInt32
    var height: UInt32
    var scale: Float
    var supersample: UInt32
}

enum MetalBenchmarkError: Error, LocalizedError {
    case deviceUnavailable
    case functionNotFound
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
            case .deviceUnavailable: return "No Metal device/command queue available on this machine."
            case .functionNotFound: return "renderFigure9 function not found after compiling the library."
            case .bufferAllocationFailed: return "Failed to allocate a Metal buffer."
        }
    }
}

/// Not actor-isolated on purpose (default isolation for this project is
/// `nonisolated`) -- every method here does blocking Metal calls
/// (`waitUntilCompleted`), so callers should run them from a background
/// `Task.detached`, mirroring how `NodeRenderer.renderPixels` is invoked.
final class Figure9MetalBenchmark {
    let device: MTLDevice
    let queue: MTLCommandQueue

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw MetalBenchmarkError.deviceUnavailable
        }
        self.device = device
        self.queue = queue
    }

    struct CompileResult {
        let pipeline: MTLComputePipelineState
        let duration: Duration
    }

    /// Compiles `figure9MetalSource` from scratch -- the realistic stand-in
    /// for "a freshly mutated tree's generated shader source," since a real
    /// codegen backend can't rely on a precompiled .metallib for content
    /// that doesn't exist until the tree is built.
    func compilePipeline() throws -> CompileResult {
        let clock = ContinuousClock()
        let start = clock.now
        let library = try device.makeLibrary(source: figure9MetalSource, options: nil)
        guard let function = library.makeFunction(name: "renderFigure9") else {
            throw MetalBenchmarkError.functionNotFound
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        let duration = clock.now - start
        return CompileResult(pipeline: pipeline, duration: duration)
    }

    struct RenderResult {
        let data: [Value]
        let dispatchDuration: Duration
        let readbackDuration: Duration
    }

    func render(pipeline: MTLComputePipelineState, width: Int, height: Int, scale: Float, supersample: Int) throws -> RenderResult {
        let clock = ContinuousClock()

        let pixelCount = width * height
        let outputLength = pixelCount * MemoryLayout<SIMD4<Float>>.stride
        guard let outputBuffer = device.makeBuffer(length: outputLength, options: .storageModeShared) else {
            throw MetalBenchmarkError.bufferAllocationFailed
        }
        var params = Figure9Params(width: UInt32(width), height: UInt32(height), scale: scale, supersample: UInt32(supersample))
        guard let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<Figure9Params>.stride, options: .storageModeShared) else {
            throw MetalBenchmarkError.bufferAllocationFailed
        }

        let dispatchStart = clock.now
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalBenchmarkError.bufferAllocationFailed
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 1)

        let tgWidth = pipeline.threadExecutionWidth
        let tgHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / tgWidth)
        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: tgHeight, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let dispatchDuration = clock.now - dispatchStart

        let readbackStart = clock.now
        let ptr = outputBuffer.contents().bindMemory(to: Float.self, capacity: pixelCount * 4)
        var data = [Value](repeating: .zero, count: pixelCount)
        for i in 0..<pixelCount {
            let base = i * 4
            data[i] = Value(ComponentType(ptr[base]), ComponentType(ptr[base + 1]), ComponentType(ptr[base + 2]))
        }
        let readbackDuration = clock.now - readbackStart

        return RenderResult(data: data, dispatchDuration: dispatchDuration, readbackDuration: readbackDuration)
    }
}

// MARK: - Report

private struct BenchmarkReport {
    let resolution: CGSize
    let supersample: Int
    let iterations: Int

    let cpuRenderDuration: Duration
    let cpuImageDuration: Duration

    let gpuCompileDuration: Duration
    let gpuFirstDispatchDuration: Duration
    let gpuFirstReadbackDuration: Duration
    let gpuWarmDispatchDurations: [Duration]
    let gpuWarmReadbackDurations: [Duration]

    let maxAbsDiff: Double
    let meanAbsDiff: Double

    let debugConstantsWarning: String?

    var gpuWarmDispatchMean: Duration {
        guard !gpuWarmDispatchDurations.isEmpty else { return .zero }
        let totalMs = gpuWarmDispatchDurations.reduce(0.0) { $0 + $1.milliseconds }
        return .milliseconds(totalMs / Double(gpuWarmDispatchDurations.count))
    }

    var gpuWarmReadbackMean: Duration {
        guard !gpuWarmReadbackDurations.isEmpty else { return .zero }
        let totalMs = gpuWarmReadbackDurations.reduce(0.0) { $0 + $1.milliseconds }
        return .milliseconds(totalMs / Double(gpuWarmReadbackDurations.count))
    }

    var cpuTotal: Duration { cpuRenderDuration + cpuImageDuration }
    var gpuColdTotal: Duration { gpuCompileDuration + gpuFirstDispatchDuration + gpuFirstReadbackDuration }
    var gpuWarmTotal: Duration { gpuWarmDispatchMean + gpuWarmReadbackMean }
}

private extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000.0 + Double(attoseconds) * 1e-15
    }

    static func milliseconds(_ ms: Double) -> Duration {
        .seconds(ms / 1000.0)
    }

    var formattedMs: String {
        String(format: "%.2f ms", milliseconds)
    }
}

// MARK: - View

struct MetalBenchmarkView: View {
    private static let sizes: [(label: String, size: CGSize)] = [
        ("Preview (200×200)", CGSize(width: 200, height: 200)),
        ("Full (800×800)", CGSize(width: 800, height: 800)),
    ]

    @State private var sizeIndex = 0
    @State private var warmIterations = 5
    @State private var isRunning = false
    @State private var report: BenchmarkReport?
    @State private var errorMessage: String?
    @State private var cpuImage: CGImage?
    @State private var gpuImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Figure 9: CPU vs. hand-written Metal kernel")
                .font(.title3.bold())
            Text("One-off feasibility spike, not a general tree→MSL compiler. See file comments for what's baked in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Resolution", selection: $sizeIndex) {
                ForEach(Self.sizes.indices, id: \.self) { i in
                    Text(Self.sizes[i].label).tag(i)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Warm GPU iterations to average: \(warmIterations)", value: $warmIterations, in: 1...50)

            Button(isRunning ? "Running…" : "Run Benchmark") {
                runBenchmark()
            }
            .disabled(isRunning)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let report {
                reportView(report)
            }

            HStack(alignment: .top, spacing: 16) {
                imageColumn(title: "CPU", image: cpuImage)
                imageColumn(title: "Metal", image: gpuImage)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 560)
    }

    private func imageColumn(title: String, image: CGImage?) -> some View {
        VStack {
            Text(title).font(.caption.bold())
            if let image {
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 220, height: 220)
            }
        }
    }

    private func reportView(_ report: BenchmarkReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let warning = report.debugConstantsWarning {
                Text("⚠️ \(warning)")
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("").font(.caption.bold())
                    Text("CPU").font(.caption.bold())
                    Text("Metal (cold)").font(.caption.bold())
                    Text("Metal (warm mean)").font(.caption.bold())
                }
                GridRow {
                    Text("Node-tree evaluation")
                    Text(report.cpuRenderDuration.formattedMs)
                    Text((report.gpuCompileDuration + report.gpuFirstDispatchDuration).formattedMs)
                        .help("Includes shader compile + first dispatch")
                    Text(report.gpuWarmDispatchMean.formattedMs)
                }
                GridRow {
                    Text("Readback / image pack")
                    Text(report.cpuImageDuration.formattedMs)
                    Text(report.gpuFirstReadbackDuration.formattedMs)
                    Text(report.gpuWarmReadbackMean.formattedMs)
                }
                GridRow {
                    Text("Total").bold()
                    Text(report.cpuTotal.formattedMs).bold()
                    Text(report.gpuColdTotal.formattedMs).bold()
                    Text(report.gpuWarmTotal.formattedMs).bold()
                }
            }
            .font(.system(.body, design: .monospaced))

            Divider()

            Text("Shader compile time alone: \(report.gpuCompileDuration.formattedMs) (over \(report.iterations) warm iterations, amortizes to \((report.gpuCompileDuration.milliseconds / Double(report.iterations)).formatted(.number.precision(.fractionLength(3)))) ms/frame)")
                .font(.caption)
            Text("Speedup vs CPU, cold (incl. compile): \(String(format: "%.2f", report.cpuTotal.milliseconds / max(report.gpuColdTotal.milliseconds, 0.001)))×")
                .font(.caption)
            Text("Speedup vs CPU, warm (pipeline reused): \(String(format: "%.2f", report.cpuTotal.milliseconds / max(report.gpuWarmTotal.milliseconds, 0.001)))×")
                .font(.caption)

            Divider()

            Text("CPU/GPU parity — max abs diff: \(String(format: "%.6f", report.maxAbsDiff)), mean abs diff: \(String(format: "%.6f", report.meanAbsDiff))")
                .font(.caption)
            Text("(float32 GPU vs. float64 CPU math, so small nonzero diffs are expected; large ones mean the port is wrong.)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func runBenchmark() {
        isRunning = true
        errorMessage = nil
        let size = Self.sizes[sizeIndex].size
        let iterations = warmIterations
        let supersample = UserDefaults.standard.isSupersamplingEnabled ? 4 : 1

        let figure9Expression = ContentView.sampleExpressions["Figure 9"]!

        Task {
            do {
                let (result, cpuData, gpuData) = try await Self.runOffMainActor(figure9Expression: figure9Expression, size: size, supersample: supersample, iterations: iterations)
                report = result
                cpuImage = Self.makeCGImage(data: cpuData, width: Int(size.width), height: Int(size.height))
                gpuImage = Self.makeCGImage(data: gpuData, width: Int(size.width), height: Int(size.height))
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }

    private static func runOffMainActor(figure9Expression: String, size: CGSize, supersample: Int, iterations: Int) async throws -> (BenchmarkReport, [Value], [Value]) {
        try await Task.detached {
            let width = Int(size.width)
            let height = Int(size.height)

            // --- CPU path: identical calls RenderedImageView makes today ---
            let parser = Parser()
            let node = try parser.parse(figure9Expression)
            let cpuRenderer = await NodeRenderer(node: node, evaluator: Evaluator(size: size))

            let clock = ContinuousClock()
            let renderStart = clock.now
            await cpuRenderer.render()
            let cpuRenderDuration = clock.now - renderStart

            let imageStart = clock.now
            _ = await cpuRenderer.cgImage()
            let cpuImageDuration = clock.now - imageStart

            // --- GPU path ---
            let benchmark = try Figure9MetalBenchmark()
            let compileResult = try benchmark.compilePipeline()
            let firstRun = try benchmark.render(pipeline: compileResult.pipeline, width: width, height: height, scale: 1.0, supersample: supersample)

            var warmDispatch: [Duration] = []
            var warmReadback: [Duration] = []
            var lastRun = firstRun
            for _ in 0..<iterations {
                let run = try benchmark.render(pipeline: compileResult.pipeline, width: width, height: height, scale: 1.0, supersample: supersample)
                warmDispatch.append(run.dispatchDuration)
                warmReadback.append(run.readbackDuration)
                lastRun = run
            }

            // --- Parity check against the live ColorGradient debug constants ---
            var warning: String? = nil
            if ColorGradient.debugDelta != assumedDebugDelta ||
                ColorGradient.debugHeightFactor != assumedDebugHeightFactor ||
                ColorGradient.debugLightZ != assumedDebugLightZ ||
                ColorGradient.debugSharedNormal != assumedDebugSharedNormal {
                warning = "ColorGradient.debug* has drifted from the values baked into the Metal kernel (delta=\(ColorGradient.debugDelta), heightFactor=\(ColorGradient.debugHeightFactor), lightZ=\(ColorGradient.debugLightZ), sharedNormal=\(ColorGradient.debugSharedNormal)). The parity diff below is not meaningful until the kernel constants are updated to match."
            }

            var maxDiff = 0.0
            var sumDiff = 0.0
            let cpuData = await cpuRenderer.data
            for i in 0..<cpuData.count {
                let d = abs(cpuData[i] - lastRun.data[i])
                let m = Swift.max(d.x, d.y, d.z)
                maxDiff = Swift.max(maxDiff, m)
                sumDiff += Double(d.x + d.y + d.z) / 3.0
            }
            let meanDiff = sumDiff / Double(cpuData.count)

            let report = BenchmarkReport(
                resolution: size,
                supersample: supersample,
                iterations: iterations,
                cpuRenderDuration: cpuRenderDuration,
                cpuImageDuration: cpuImageDuration,
                gpuCompileDuration: compileResult.duration,
                gpuFirstDispatchDuration: firstRun.dispatchDuration,
                gpuFirstReadbackDuration: firstRun.readbackDuration,
                gpuWarmDispatchDurations: warmDispatch,
                gpuWarmReadbackDurations: warmReadback,
                maxAbsDiff: maxDiff,
                meanAbsDiff: meanDiff,
                debugConstantsWarning: warning
            )

            return (report, cpuData, lastRun.data)
        }.value
    }

    private static func makeCGImage(data: [Value], width: Int, height: Int) -> CGImage? {
        var pixelData = [UInt8](repeating: 0, count: width * height * 3)
        data.withUnsafeBufferPointer { src in
            pixelData.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    let clamped = clamp(src[i], min: Value.zero, max: Value.one)
                    let mapped = clamped * 255.0
                    let base = i * 3
                    dst[base] = UInt8(clamping: Int(mapped.x))
                    dst[base + 1] = UInt8(clamping: Int(mapped.y))
                    dst[base + 2] = UInt8(clamping: Int(mapped.z))
                }
            }
        }

        guard let providerRef = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

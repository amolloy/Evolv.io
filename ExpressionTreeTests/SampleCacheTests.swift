//
//  SampleCacheTests.swift
//  ExpressionTreeTests
//
//  A `fn grid(...)` child (blur's source) is rendered into a texture before
//  the main pass and read from there (see MetalRenderContext's
//  fillSampleCaches). That must look the same as calling it directly.
//

import Testing
import Foundation
@testable import ExpressionTree

@Suite(.serialized) struct SampleCacheTests {
	private static let bundledGenotypesDirectory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appendingPathComponent("Evolv.io/Resources/BundledGenotypes")

	private static let square = CGRect(x: -1, y: -1, width: 2, height: 2)

	private static func genotype(named name: String) throws -> any Node {
		let (genotypes, _) = GenotypeLibrary.scan(roots: [(bundledGenotypesDirectory, .bundled)])
		let genotype = try #require(genotypes.first { $0.displayName == name })
		return try Parser().parse(genotype.expression)
	}

	/// The largest per-channel difference, and how many pixels differ by
	/// more than 1e-3.
	private static func compare(_ a: [Value], _ b: [Value]) -> (maxDifference: Double, differing: Int) {
		var maxDifference = 0.0
		var differing = 0
		for (p, q) in zip(a, b) {
			let d = Swift.max(Swift.abs(p.x - q.x), Swift.abs(p.y - q.y), Swift.abs(p.z - q.z))
			maxDifference = Swift.max(maxDifference, d)
			if d > 1e-3 { differing += 1 }
		}
		return (maxDifference, differing)
	}

	private static func expectSame(_ expression: String, bounds: CGRect = square, width: Int = 64, height: Int = 64) throws {
		let node = try Parser().parse(expression)
		let cached = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: bounds, supersample: 2)
		let direct = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: bounds, supersample: 2, sampleCaching: false)
		let (maxDifference, differing) = compare(cached, direct)
		print("SAMPLECACHE \(expression) max \(maxDifference) differing \(differing)")
		#expect(maxDifference < 1e-4, "\(expression): cached and direct renders differ by up to \(maxDifference) (\(differing) pixels over 1e-3)")
	}

	@Test func blurOfASmoothSourceMatchesDirectCalls() throws {
		try Self.expectSame("(blur (sin (* x 7)) 3.1)")
	}

	/// The inner blur's texture is filled first; the outer blur's fill reads
	/// it. (Rendering this without textures, for comparison, is millions of
	/// evaluations per sample, which macOS kills.) A normalized symmetric
	/// blur leaves x and x*y unchanged, and so does bilinear interpolation
	/// between cell centres, so the expected image is known exactly.
	@Test func nestedBlursKeepBilinearFunctions() throws {
		for (expression, expected) in [("(blur (blur x 2) 3.1)", { (x: Double, y: Double) in x }),
									   ("(blur (blur (* x y) 2) 3.1)", { (x: Double, y: Double) in x * y })] {
			let node = try Parser().parse(expression)
			let size = 64
			let image = try MetalRenderContext.shared.render(node: node, width: size, height: size, bounds: Self.square, supersample: 1)
			var maxError = 0.0
			for row in 0..<size {
				for column in 0..<size {
					let x = (Double(column) + 0.5) / Double(size) * 2 - 1
					let y = (Double(size - 1 - row) + 0.5) / Double(size) * 2 - 1
					maxError = Swift.max(maxError, Swift.abs(image[row * size + column].x - expected(x, y)))
				}
			}
			#expect(maxError < 1e-4, "\(expression): off by up to \(maxError)")
		}
	}

	/// Sigma 12 spaces the taps 4 cells apart, reaching 40 cells out --
	/// past the texture's margin at the image's edge, so those taps take
	/// the direct path.
	@Test func tapsOutsideTheTextureMatchDirectCalls() throws {
		try Self.expectSame("(blur (sin (* x 7)) 12)", bounds: CGRect(x: 0.3, y: -0.2, width: 0.4, height: 0.4))
	}

	/// grad-direction samples blur off the image, and blur's taps in turn
	/// reach the texture's margin.
	@Test func sampledBlurMatchesDirectCalls() throws {
		try Self.expectSame("(grad-direction (blur (sin (* x 7)) 3.1) 1.46 5.9)")
	}

	/// Every bundled genotype with a blur. Figure 13's `if` mask has hard
	/// edges, so a tap coordinate a rounding error apart can land on the
	/// other side of one: allow a handful of pixels there, no more.
	@Test func bundledGenotypesMatchDirectCalls() throws {
		let (genotypes, _) = GenotypeLibrary.scan(roots: [(Self.bundledGenotypesDirectory, .bundled)])
		var checked = 0
		for genotype in genotypes where genotype.expression.contains("blur") {
			let node = try Parser().parse(genotype.expression)
			let cached = try MetalRenderContext.shared.render(node: node, width: 200, height: 200, bounds: Self.square, supersample: 2)
			let direct = try MetalRenderContext.shared.render(node: node, width: 200, height: 200, bounds: Self.square, supersample: 2, sampleCaching: false)
			let (maxDifference, differing) = Self.compare(cached, direct)
			print("SAMPLECACHE \(genotype.displayName) max \(maxDifference) differing \(differing)")
			#expect(differing <= 20, "\(genotype.displayName): \(differing) pixels differ by more than 1e-3 (max \(maxDifference))")
			checked += 1
		}
		#expect(checked > 0)
	}

	@Test func gridIsOnlyAllowedOnAFunctionParam() throws {
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"g\"(v: grid(0.1)) { return v }").parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"g\"(v: fn grid(coord.x)) { return v(coord) }").parseTemplate()
		}
	}

	/// Renders `expression` with blur's `percell` sums read from textures
	/// and computed in place; returns the largest difference.
	private static func percellDifference(_ expression: String, size: Int = 128) throws -> Double {
		let node = try Parser().parse(expression)
		defer {
			DSLInterpreter.cachesPercellBlocks = true
			MetalRenderContext.shared.clearPipelineCache()
		}
		var images: [[Value]] = []
		for cached in [true, false] {
			DSLInterpreter.cachesPercellBlocks = cached
			MetalRenderContext.shared.clearPipelineCache()
			images.append(try MetalRenderContext.shared.render(node: node, width: size, height: size, bounds: square, supersample: 1))
		}
		let maxDifference = compare(images[0], images[1]).maxDifference
		print("PERCELL \(expression) max \(maxDifference)")
		return maxDifference
	}

	/// The cached sums are the same sums, but compiled in another function,
	/// which can round differently in the last bit or two (fast math); on
	/// its own blur is off by about 1e-7. grad-direction's finite
	/// differences magnify that.
	@Test func percellBlurMatchesComputingInPlace() throws {
		#expect(try Self.percellDifference("(blur (sin (* x 7)) 3.1)") < 1e-6)
		#expect(try Self.percellDifference("(blur (* x y) 0.5)") < 1e-6)
		#expect(try Self.percellDifference("(grad-direction (blur (sin (* x 7)) 3.1) 1.46 5.9)") < 1e-4)
	}

	/// How many textures `expression` renders before the main pass.
	private static func cacheCount(_ expression: String) throws -> Int {
		let context = MSLCodegenContext(sampleCaching: true)
		_ = try Parser().parse(expression).codegenMSL(into: context)
		return context.sampleCaches.count
	}

	/// The sums are cached only when everything they read besides the cell
	/// is the same everywhere: a radius depending on x or y computes them in
	/// place (blur's source is still cached).
	@Test func percellNeedsAUniformRadius() throws {
		#expect(try Self.cacheCount("(blur (sin (* x 7)) 3.1)") == 2)
		#expect(try Self.cacheCount("(blur (sin (* x 7)) (sin 2.0))") == 2)
		#expect(try Self.cacheCount("(blur (sin (* x 7)) (* x 3))") == 1)
		#expect(try Self.cacheCount("(blur (sin (* x 7)) (bw-noise 0.3 0.5))") == 1)
		#expect(try Self.percellDifference("(blur (sin (* x 7)) (+ 2 (* x 3)))", size: 64) == 0)
	}

	@Test func percellSpacingFollowsGridRules() throws {
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"p\"(v) { let c: float2 = coord\n let s = percell(c, coord.x) { v }\n return s }").parseTemplate()
		}
		_ = try DSLParser("node \"p\"(v) { let c: float2 = coord\n let s = percell(c, 2.0 / $w) { v }\n return s }").parseTemplate()
	}

	/// Not a check: prints how long Figure 13 takes with and without the
	/// texture, for comparing render-path changes.
	@Test func timeFigure13() throws {
		let node = try Self.genotype(named: "Figure 13")
		for caching in [true, false] {
			_ = try MetalRenderContext.shared.render(node: node, width: 16, height: 16, bounds: Self.square, supersample: 1, sampleCaching: caching)
			let start = Date()
			_ = try MetalRenderContext.shared.render(node: node, width: 400, height: 400, bounds: Self.square, supersample: 2, sampleCaching: caching)
			print("TIMING Figure 13 400x400 ss2 caching \(caching): \(Date().timeIntervalSince(start)) s")
		}
	}
}

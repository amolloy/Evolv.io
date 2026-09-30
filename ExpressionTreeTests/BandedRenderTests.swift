//
//  BandedRenderTests.swift
//  ExpressionTreeTests
//
//  MetalRenderContext splits a render into passes (a band of rows and a
//  run of each pixel's supersamples, one command buffer each) so a heavy
//  tree can't run long enough for macOS to kill it. The split must not
//  change a single pixel.
//

import Testing
import Foundation
@testable import ExpressionTree

struct BandedRenderTests {
	private static let bundledGenotypesDirectory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appendingPathComponent("Evolv.io/Resources/BundledGenotypes")

	private static let square = CGRect(x: -1, y: -1, width: 2, height: 2)

	/// Each row gets its own y, so a band written at the wrong row offset
	/// shows up as a wrong value.
	@Test func bandsLandOnTheirOwnRows() throws {
		let node = try Parser().parse("y")
		let width = 64, height = 300
		// Adaptive passes start at 4096 threads: 64 rows, then resize.
		let adaptive = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 1)
		let tiny = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 1, fixedBandRows: 7, fixedSamplesPerPass: 1)
		for row in 0..<height {
			let expected = (Double(height - 1 - row) + 0.5) / Double(height) * 2 - 1
			for column in [0, width - 1] {
				#expect(Swift.abs(adaptive[row * width + column].x - expected) < 1e-6, "row \(row): \(adaptive[row * width + column].x) vs \(expected)")
				#expect(Swift.abs(tiny[row * width + column].x - expected) < 1e-6, "row \(row): \(tiny[row * width + column].x) vs \(expected)")
			}
		}
	}

	/// Every bundled genotype the registry can parse, rendered in 7-row
	/// bands one supersample at a time, in 3-sample passes, and adaptively,
	/// matches one whole-image, all-samples dispatch exactly (same process,
	/// so the same Perlin table).
	@Test func bandingIsPixelIdenticalForEveryBundledGenotype() throws {
		let (genotypes, issues) = GenotypeLibrary.scan(roots: [(Self.bundledGenotypesDirectory, .bundled)])
		#expect(issues.isEmpty)
		let width = 200, height = 160
		var checked = 0
		for genotype in genotypes {
			guard let node = try? Parser().parse(genotype.expression) else { continue }
			let whole = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 3, fixedBandRows: height, fixedSamplesPerPass: 9)
			let banded = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 3, fixedBandRows: 7, fixedSamplesPerPass: 1)
			let runs = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 3, fixedBandRows: 50, fixedSamplesPerPass: 4)
			let adaptive = try MetalRenderContext.shared.render(node: node, width: width, height: height, bounds: Self.square, supersample: 3)
			#expect(banded == whole, "\(genotype.displayName): 7-row, 1-sample passes differ from one dispatch")
			#expect(runs == whole, "\(genotype.displayName): 50-row, 4-sample passes differ from one dispatch")
			#expect(adaptive == whole, "\(genotype.displayName): adaptive bands differ from one dispatch")
			checked += 1
		}
		// Everything but Figure 12 (it needs atan and vector, which don't exist yet).
		#expect(checked >= genotypes.count - 1, "only \(checked) of \(genotypes.count) genotypes parsed")
	}
}

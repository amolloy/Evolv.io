//
//  TapCacheTests.swift
//  ExpressionTreeTests
//
//  With tap caching on, a `fn taps(...)` child (color-grad's, bump's and
//  grad-direction's source) is rendered into a texture first and its taps
//  interpolate it bilinearly (see MetalRenderContext's fillSampleCaches).
//  Bilinear interpolation is exact for a + bx + cy + dxy, so for those
//  sources the cached render must match the exact one.
//

import Testing
import Foundation
@testable import ExpressionTree

@Suite(.serialized) struct TapCacheTests {
	private static let square = CGRect(x: -1, y: -1, width: 2, height: 2)

	private static func expectSame(_ expression: String, bounds: CGRect = square) throws {
		let node = try Parser().parse(expression)
		let exact = try MetalRenderContext.shared.render(node: node, width: 64, height: 64, bounds: bounds, supersample: 2)
		for resolution in [1.0, 2.0, 4.0] {
			let cached = try MetalRenderContext.shared.render(node: node, width: 64, height: 64, bounds: bounds, supersample: 2,
															  tapCache: TapCacheSettings(resolution: resolution))
			var maxDifference = 0.0
			for (p, q) in zip(exact, cached) {
				maxDifference = Swift.max(maxDifference, Swift.abs(p.x - q.x), Swift.abs(p.y - q.y), Swift.abs(p.z - q.z))
			}
			#expect(maxDifference < 1e-4, "\(expression) at \(resolution)x: cached and exact renders differ by up to \(maxDifference)")
		}
	}

	@Test func bilinearSourcesMatchExactRenders() throws {
		try Self.expectSame("(grad-direction (* x y) 1.46 5.9)")
		try Self.expectSame("(bump (+ x (* x y)) #(1 0.5 0.2) 0.78 #(0.18 0.28 0.58) #(0.4 0.92 0.58) 10.6 0.23 0.91)")
		try Self.expectSame("(color-grad (* x y) 3.1 1.86 #(0.95 0.7 0.59) 1.35)")
	}

	/// color-grad of x*y is linear, so the outer color-grad's source is too.
	/// The inner texture is filled first and reaches the outer one's taps
	/// beyond the image; off-centre bounds check the texel placement.
	@Test func nestedCachesMatchExactRenders() throws {
		let expression = "(color-grad (+ x (color-grad (* x y) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 3.1 1.9 #(0.95 0.7 0.35) 1.35)"
		try Self.expectSame(expression)
		try Self.expectSame(expression, bounds: CGRect(x: 0.3, y: -0.2, width: 0.4, height: 0.25))
	}

	/// Guards the tests above against passing because every tap fell back
	/// to a direct call: a curved source must come out (slightly) different.
	@Test func curvedSourcesAreInterpolated() throws {
		let node = try Parser().parse("(grad-direction (sin (* x 40)) 1.46 5.9)")
		let exact = try MetalRenderContext.shared.render(node: node, width: 64, height: 64, bounds: Self.square, supersample: 1)
		let cached = try MetalRenderContext.shared.render(node: node, width: 64, height: 64, bounds: Self.square, supersample: 1,
														  tapCache: TapCacheSettings(resolution: 1))
		let differing = zip(exact, cached).filter { Swift.abs($0.0.x - $0.1.x) > 1e-4 }.count
		#expect(differing > exact.count / 2, "only \(differing) of \(exact.count) pixels changed")
	}

	@Test func tapsAreOnlyAllowedOnAFunctionParam() throws {
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"g\"(v: taps(0.1)) { return v }").parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"g\"(v: fn taps(coord.x)) { return v(coord) }").parseTemplate()
		}
		#expect(throws: DSLParseError.self) {
			_ = try DSLParser("node \"g\"(v: fn grid(0.1) taps(0.1)) { return v(coord) }").parseTemplate()
		}
	}
}

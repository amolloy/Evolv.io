//
//  NodeRenderer.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/13/25.
//

import ExpressionTree
import CoreGraphics
import Foundation
import simd
import SwiftUI

extension UserDefaults {
	static let supersamplingEnabledKey = "supersamplingEnabled"

	var isSupersamplingEnabled: Bool {
		object(forKey: Self.supersamplingEnabledKey) as? Bool ?? true
	}
}

@MainActor
class NodeRenderer: ObservableObject {
	let node: any Node
	let evaluator: Evaluator
	let scale: ComponentType
	var data: Array<Value>
	var maxValue: Value = Value(-.infinity, -.infinity, -.infinity)
	var minValue: Value = Value(.infinity, .infinity, .infinity)

	@Published var displayMax: Value = Value.one
	@Published var displayMin: Value = Value.zero

	init(node: any Node,
		 evaluator: Evaluator,
		 scale: ComponentType = 1) {
		self.node = node
		self.evaluator = evaluator
		self.scale = scale
		self.data = Array(repeating: Value(0, 0, 0), count: Int(evaluator.size.width * evaluator.size.height))
	}

	func render() async {
		let width = Int(evaluator.size.width)
		let height = Int(evaluator.size.height)
		let node = self.node
		let evaluator = self.evaluator
		let scale = self.scale
		let supersample = UserDefaults.standard.isSupersamplingEnabled ? 4 : 1

		let rendered = await Task.detached(priority: .userInitiated) {
			Self.renderPixels(node: node,
							   evaluator: evaluator,
							   scale: scale,
							   width: width,
							   height: height,
							   supersample: supersample)
		}.value

		data = rendered.data
		maxValue = rendered.maxValue
		minValue = rendered.minValue
	}

	/// Renders via the shared Metal pipeline cache (see `Evaluator.render`
	/// and `MetalRenderContext`) rather than a CPU per-pixel loop -- per the
	/// Metal codegen migration plan, there is no CPU rendering path anymore.
	nonisolated private static func renderPixels(node: any Node,
									  evaluator: Evaluator,
									  scale: ComponentType,
									  width: Int,
									  height: Int,
									  supersample: Int) -> (data: [Value], maxValue: Value, minValue: Value) {
		let data: [Value]
		do {
			data = try evaluator.render(node: node, scale: scale, supersample: supersample)
		} catch {
			print("Metal render failed: \(error)")
			data = Array(repeating: Value.zero, count: width * height)
		}

		var maxValue = Value(-.infinity, -.infinity, -.infinity)
		var minValue = Value(.infinity, .infinity, .infinity)
		for pixel in data {
			maxValue = max(maxValue, pixel)
			minValue = min(minValue, pixel)
		}

		return (data, maxValue, minValue)
	}

	func cgImage() -> CGImage? {
		let width = Int(evaluator.size.width)
		let height = Int(evaluator.size.height)

		let bytesPerPixel = 3
		let bitsPerComponent = 8
		let bytesPerRow = bytesPerPixel * width

		let displayMin = self.displayMin
		let range = displayMax - displayMin

		var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
		data.withUnsafeBufferPointer { src in
			pixelData.withUnsafeMutableBufferPointer { dst in
				for i in 0..<src.count {
//					let mapped = src[i].triangleFolded() * 255.0

					let normalized = (src[i] - displayMin) / range
					let clamped = clamp(normalized, min: Value.zero, max: Value.one)
					let mapped = clamped * 255.0

					let base = i * bytesPerPixel
					dst[base] = UInt8(clamping: Int(mapped.x))
					dst[base + 1] = UInt8(clamping: Int(mapped.y))
					dst[base + 2] = UInt8(clamping: Int(mapped.z))
				}
			}
		}

		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

		guard let providerRef = CGDataProvider(data: Data(pixelData) as CFData) else {
			return nil
		}

		return CGImage(
			width: width,
			height: height,
			bitsPerComponent: bitsPerComponent,
			bitsPerPixel: bitsPerComponent * bytesPerPixel,
			bytesPerRow: bytesPerRow,
			space: rgbColorSpace,
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
			provider: providerRef,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)
	}

	func copyImageToPasteboard() {
#if canImport(AppKit)
		guard let pngData = self.cgImage()?.pngData() else {
			print("Failed to convert CGImage to PNG data.")
			return
		}

		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		if pasteboard.setData(pngData, forType: .png) {
			print("Image copied to pasteboard.")
		} else {
			print("Failed to write image to pasteboard.")
		}
#endif
	}
}

extension CGImage {
	func pngData() -> Data? {
		guard let mutableData = CFDataCreateMutable(nil, 0) else { return nil }
		guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, self, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return mutableData as Data
	}
}

extension SIMD3 where Scalar == ComponentType {
	/// True periodic triangle folding: bounces continuously between 0.0 and 1.0
	public func triangleFolded() -> SIMD3<ComponentType> {
		func fold(_ v: ComponentType) -> ComponentType {
			let m = v.truncatingRemainder(dividingBy: 2.0)
			let pos = m < 0 ? m + 2.0 : m
			return pos > 1.0 ? 2.0 - pos : pos
		}
		return SIMD3<ComponentType>(fold(self.x), fold(self.y), fold(self.z))
	}

	/// Periodic fractional wrap in [0.0, 1.0)
	public func fract() -> SIMD3<ComponentType> {
		return SIMD3<ComponentType>(
			self.x - floor(self.x),
			self.y - floor(self.y),
			self.z - floor(self.z)
		)
	}
}

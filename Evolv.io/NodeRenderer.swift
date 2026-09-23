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
		let result = evaluator.evaluate(node: node)

		let scaleFactor = 2.0 * scale
		let scaleOffset = scaleFactor / 2.0

		let supersample = UserDefaults.standard.isSupersamplingEnabled ? 4 : 1
		let dx = scaleFactor / ComponentType(width)
		let dy = scaleFactor / ComponentType(height)

		for y in 0..<height {
			let yc = (ComponentType(height - 1 - y) + 0.5) / ComponentType(height) * scaleFactor - scaleOffset
			for x in 0..<width {
				let xc = (ComponentType(x) + 0.5) / ComponentType(width) * scaleFactor - scaleOffset

				var accumulated = Value.zero
				for sy in 0..<supersample {
					let subYc = yc + (ComponentType(sy) + 0.5) / ComponentType(supersample) * dy - dy / 2.0
					for sx in 0..<supersample {
						let subXc = xc + (ComponentType(sx) + 0.5) / ComponentType(supersample) * dx - dx / 2.0
						accumulated += result.value(at: Coordinate(x: subXc, y: subYc)).sanitized()
					}
				}
				let pixel = accumulated / ComponentType(supersample * supersample)

				maxValue = max(pixel, maxValue)
				minValue = min(pixel, minValue)

				data[y * width + x] = pixel
			}
		}
	}

	func cgImage() -> CGImage? {
		let width = Int(evaluator.size.width)
		let height = Int(evaluator.size.height)

		let pixelData: [UInt8] = data.flatMap { pixel in
//			let mapped = pixel.triangleFolded() * 255.0

			let normalized = (pixel - displayMin) / (displayMax - displayMin)
			let clamped = clamp(normalized, min: Value.zero, max: Value.one)
			let mapped = clamped * 255.0

			let r = UInt8(clamping: Int(mapped.x))
			let g = UInt8(clamping: Int(mapped.y))
			let b = UInt8(clamping: Int(mapped.z))
			return [r, g, b]
		}

		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
		let bytesPerPixel = 3
		let bitsPerComponent = 8
		let bytesPerRow = bytesPerPixel * width

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

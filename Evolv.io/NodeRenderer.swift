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

		for y in 0..<height {
			let yc = ComponentType(height - y) / ComponentType(height) * scaleFactor - scaleOffset
			for x in 0..<width {
				let xc = ComponentType(x) / ComponentType(width) * scaleFactor - scaleOffset

				let pixel = result.value(at: Coordinate(x: xc,
														y: yc))

				maxValue = max(pixel, maxValue)
				minValue = min(pixel, minValue)

				data[y * width + x] = pixel.sanitized()
			}
		}
	}

	func cgImage() -> CGImage? {
		let width = Int(evaluator.size.width)
		let height = Int(evaluator.size.height)

		let pixelData: [UInt8] = data.flatMap { pixel in
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

fileprivate extension CGImage {
	func pngData() -> Data? {
		guard let mutableData = CFDataCreateMutable(nil, 0) else { return nil }
		guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, self, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return mutableData as Data
	}
}

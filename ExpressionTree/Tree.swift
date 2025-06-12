//
//  Tree.swift
//  Tree
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation
import CoreImage

public class Tree {
	public typealias ComponentType = Double
	public typealias Value = SIMD3<ComponentType>
	public typealias Coordinate = SIMD2<ComponentType>

	let width: Int
	let height: Int
	let root: any Node

	public init(width: Int, height: Int, root: any Node) {
		self.width = width
		self.height = height
		self.root = root
	}

	public func evaluate() -> CGImage? {
		let evaluator = Evaluator(width: width, height: height)
		let result = evaluator.evaluate(root: root)

		var data = Array(repeating: Value(0, 0, 0), count: width * height)
		for y in 0..<height {
			let yc = ComponentType(height - y) / ComponentType(height) * 2.0 - 1.0
			for x in 0..<width {
				let xc = ComponentType(x) / ComponentType(width) * 2.0 - 1.0

				data[y * width + x] = result.sampleBilinear(at: Coordinate(x: xc,
																		   y: yc))
			}
		}

		let pixelData: [UInt8] = data.flatMap { pixel in
			let r = UInt8(clamping: Int(pixel.x * 255))
			let g = UInt8(clamping: Int(pixel.y * 255))
			let b = UInt8(clamping: Int(pixel.z * 255))
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

	public func toString() -> String {
		return root.toString()
	}
}

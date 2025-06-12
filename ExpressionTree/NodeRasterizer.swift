//
//  NodeRasterizer.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/12/25.
//

import CoreImage

public extension Node {
	func rasterize(size: CGSize) -> CGImage? {
		let width = Int(size.width)
		let height = Int(size.height)
		let evaluator = Evaluator(size: size)
		let result = evaluator.evaluate(node: self)

		var data = Array(repeating: Value(0, 0, 0), count: width * height)
		for y in 0..<height {
			let yc = ComponentType(height - y) / ComponentType(height) * 2.0 - 1.0
			for x in 0..<width {
				let xc = ComponentType(x) / ComponentType(width) * 2.0 - 1.0

				let pixel = result.value(at: Coordinate(x: xc,
																 y: yc))

				data[y * width + x] = pixel.sanitized()
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
}

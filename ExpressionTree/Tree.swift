//
//  Tree.swift
//  Tree
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation
import CoreImage
import simd

public typealias ComponentType = Double
public typealias Value = SIMD3<ComponentType>
public typealias Coordinate = SIMD2<ComponentType>

extension Value {
	func averageLuminance() -> ComponentType {
		return (self.x + self.y + self.z) / 3.0
	}
}

internal let epsilon: ComponentType = 1e-9

public class Tree {
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
		let result = evaluator.evaluate(node: root)

		var data = Array(repeating: Value(0, 0, 0), count: width * height)
		for y in 0..<height {
			let yc = ComponentType(height - y) / ComponentType(height) * 2.0 - 1.0
			for x in 0..<width {
				let xc = ComponentType(x) / ComponentType(width) * 2.0 - 1.0

				let pixel = result.sampleBilinear(at: Coordinate(x: xc,
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

	public func toString() -> String {
		return root.toString()
	}
}

extension SIMD3 where Scalar == ComponentType {
	/// Returns a new vector by replacing any non-finite values (NaN, infinity).
	/// - NaN values are replaced with 0.0.
	/// - Positive infinity is replaced with 1.0.
	/// - Negative infinity is replaced with -1.0.
	func sanitized() -> SIMD3<ComponentType> {
		var newX = self.x
		if newX.isNaN {
			newX = 0.0
		} else if newX.isInfinite {
			newX = newX > 0 ? 1.0 : -1.0
		}

		var newY = self.y
		if newY.isNaN {
			newY = 0.0
		} else if newY.isInfinite {
			newY = newY > 0 ? 1.0 : -1.0
		}

		var newZ = self.z
		if newZ.isNaN {
			newZ = 0.0
		} else if newZ.isInfinite {
			newZ = newZ > 0 ? 1.0 : -1.0
		}

		return SIMD3<Double>(newX, newY, newZ)
	}
}

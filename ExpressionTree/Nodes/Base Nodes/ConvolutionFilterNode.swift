//
//  ConvolutionFilter.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import Foundation
import simd

open class ConvolutionFilterNode: Node {
	public var name: String {
		fatalError("Subclass must override `name`")
	}

	public var children: [Node] {
		fatalError("Subclass must override `children`")
	}

	/// A factor to multiply the convolution result by. Subclasses can override this.
	open var factor: Double { 1.0 }

	/// A bias (offset) to add to the convolution result. Subclasses can override this.
	open var bias: Double { 0.0 }

	public func evaluate(width: Int, height: Int) -> PixelBuffer {
		let parameters = children.map { $0.evaluate(width: width, height: height) }

		guard !parameters.isEmpty else {
			return PixelBuffer(width: width, height: height)
		}

		let sourceBuffer = parameters[0]
		var result = PixelBuffer(width: width, height: height)

		for y in 0..<height {
			for x in 0..<width {
				let coord = (PixelBuffer.Coordinate(Double(x), Double(y)) / PixelBuffer.Coordinate(Double(width), Double(height))) - PixelBuffer.Coordinate(repeating: 0.5)
				let kernel = self.kernel(at: coord, parameters: parameters)

				var total = PixelBuffer.Value(repeating: 0)

				for ky in -1...1 {
					for kx in -1...1 {
						let neighborValue = sourceBuffer[x + kx, y + ky]
						let weight = kernel[kx + 1][ky + 1]
						total += neighborValue * weight
					}
				}
				result[x, y] = total * factor + bias
			}
		}

		return result
	}

	open func kernel(at coord: PixelBuffer.Coordinate, parameters: [PixelBuffer]) -> simd_double3x3 {
		fatalError("Subclass must override `kernel(at:parameters:)`")
	}
}

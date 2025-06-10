//
//  ConvolutionFilter.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import Foundation
import simd

open class ConvolutionFilterNode: Node {
	public typealias CT = PixelBuffer.ComponentType

	public var name: String {
		fatalError("Subclass must override `name`")
	}

	public var children: [Node] {
		fatalError("Subclass must override `children`")
	}

	/// A factor to multiply the convolution result by. Subclasses can override this.
	open var factor: CT { 1.0 }

	/// A bias (offset) to add to the convolution result. Subclasses can override this.
	open var bias: CT { 0.0 }

	public func evaluate(width: Int, height: Int) -> PixelBuffer {
		let parameters = children.map { $0.evaluate(width: width, height: height) }

		guard !parameters.isEmpty else {
			return PixelBuffer(width: width, height: height)
		}

		let sourceBuffer = parameters[0]
		var result = PixelBuffer(width: width, height: height)

		for y in 0..<height {
			for x in 0..<width {
				let coord = (PixelBuffer.Coordinate(CT(x), CT(y)) / PixelBuffer.Coordinate(CT(width), CT(height))) - PixelBuffer.Coordinate(repeating: 0.5)
				let kernel = self.kernel(at: coord, parameters: parameters)

				var total = PixelBuffer.Value(repeating: 0)

				for ky in -1...1 {
					for kx in -1...1 {
						let neighborValue = sourceBuffer[x + kx, y + ky]
						let weight = kernel[kx + 1, ky + 1]
						total += neighborValue * weight
					}
				}
				result[x, y] = total * factor + bias
			}
		}

		return result
	}

	open func kernel(at coord: PixelBuffer.Coordinate, parameters: [PixelBuffer]) -> Kernel<CT> {
		fatalError("Subclass must override `kernel(at:parameters:)`")
	}
}

public struct Kernel<Scalar: FloatingPoint> {
	private let weights: (
		Scalar, Scalar, Scalar,
		Scalar, Scalar, Scalar,
		Scalar, Scalar, Scalar
	)

	public init(rows: (
		(Scalar, Scalar, Scalar),
		(Scalar, Scalar, Scalar),
		(Scalar, Scalar, Scalar)
	)) {
		self.weights = (
			rows.0.0, rows.0.1, rows.0.2,
			rows.1.0, rows.1.1, rows.1.2,
			rows.2.0, rows.2.1, rows.2.2
		)
	}

	subscript(x: Int, y: Int) -> Scalar {
		let index = (y + 1) * 3 + (x + 1)
		switch index {
			case 0: return weights.0
			case 1: return weights.1
			case 2: return weights.2
			case 3: return weights.3
			case 4: return weights.4
			case 5: return weights.5
			case 6: return weights.6
			case 7: return weights.7
			case 8: return weights.8
			default: fatalError("Kernel index out of bounds")
		}
	}
}

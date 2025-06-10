//
//  Laplacian.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

import Foundation
import simd

public final class Laplacian: ConvolutionFilterNode {
	private let _children: [Node]

	public init(children: [Node]) {
		assert(children.count == 1)
		self._children = children
	}

	public override var name: String { "laplacian" }
	public override var children: [Node] { _children }

	private static let laplacianKernel = simd_double3x3(rows: [
		SIMD3<Double>(0,  1,  0),
		SIMD3<Double>(1, -4,  1),
		SIMD3<Double>(0,  1,  0)
	])

	public override func kernel(at coord: PixelBuffer.Coordinate, parameters: [PixelBuffer]) -> simd_double3x3 {
		return Self.laplacianKernel
	}

	public override var bias: Double { 0.5 }
}

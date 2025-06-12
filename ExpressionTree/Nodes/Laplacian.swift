//
//  Laplacian.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/10/25.
//

/*
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

	private static let laplacianKernel = Kernel<CT>(rows: (
		(0.0,  1.0,  0.0),
		(1.0, -4.0,  1.0),
		(0.0,  1.0,  0.0)
	))

	public override func kernel(at coord: Coordinate, parameters: [ExpressionResult]) -> Kernel<CT> {
		return Self.laplacianKernel
	}

	public override var bias: CT { 0.5 }
}

*/


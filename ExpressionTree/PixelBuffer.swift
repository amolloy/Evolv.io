//
//  PixelBuffer.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation
import simd

struct PixelBuffer {
	typealias ComponentType = Double
	typealias Value = SIMD3<ComponentType>

	let width: Int
	let height: Int
	var data: [Value]

	init(width: Int, height: Int) {
		self.width = width
		self.height = height
		self.data = Array(repeating: Value(0, 0, 0), count: width * height)
	}

	subscript(x: Int, y: Int) -> Value {
		get { data[y * width + x] }
		set { data[y * width + x] = newValue }
	}
}

extension PixelBuffer {
	func sampleBilinear(u: ComponentType, v: ComponentType) -> Value {
		let fx = (u + 0.5) * ComponentType(width  - 1)
		let fy = (v + 0.5) * ComponentType(height - 1)

		let x0 = Int(floor(fx))
		let x1 = Int(ceil(fx))
		let y0 = Int(floor(fy))
		let y1 = Int(ceil(fy))

		let tx = fx - ComponentType(x0)
		let ty = fy - ComponentType(y0)

		let p00 = self[x0, y0]
		let p10 = self[x1, y0]
		let p01 = self[x0, y1]
		let p11 = self[x1, y1]

		let top    = simd_mix(p00, p10, Value(repeating: tx))
		let bottom = simd_mix(p01, p11, Value(repeating: tx))
		let final  = simd_mix(top, bottom, Value(repeating: ty))

		return final
	}
}

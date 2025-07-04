//
//  PixelBuffer.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation
import simd
import CoreImage

public struct PixelBuffer: ExpressionResult {
	let width: Int
	let height: Int
	var data: [Value]
	
	init(width: Int, height: Int) {
		self.width = width
		self.height = height
		self.data = Array(repeating: Value(0, 0, 0), count: width * height)
	}
	
	public subscript(x: Int, y: Int) -> Value {
		get {
			let wrappedX = ((x % width) + width) % width
			let wrappedY = ((y % height) + height) % height
			return data[wrappedY * width + wrappedX]
		}
		set { data[y * width + x] = newValue }
	}

	public func value(at coord: Coordinate) -> Value {
		let f = (coord + 0.5) * Coordinate(ComponentType(width - 1), ComponentType(height - 1))

		let x0 = Int(floor(f.x))
		let x1 = Int(ceil(f.x))
		let y0 = Int(floor(f.y))
		let y1 = Int(ceil(f.y))

		let t = f - Coordinate(ComponentType(x0), ComponentType(y0))

		let p00 = self[x0, y0]
		let p10 = self[x1, y0]
		let p01 = self[x0, y1]
		let p11 = self[x1, y1]

		let top = simd_mix(p00, p10, Value(repeating: t.x))
		let bottom = simd_mix(p01, p11, Value(repeating: t.x))
		let final = simd_mix(top, bottom, Value(repeating: t.y))

		return final
	}
}

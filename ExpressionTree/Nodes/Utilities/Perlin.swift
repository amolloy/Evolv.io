//
//  Perlin.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import Foundation

struct Perlin {
	typealias ComponentType = PixelBuffer.ComponentType

	static let permutation: [Int] = (0...255).shuffled() + (0...255).shuffled()

	static func fade(_ t: ComponentType) -> ComponentType {
		t * t * t * (t * (t * 6 - 15) + 10)
	}

	static func lerp(_ t: ComponentType, _ a: ComponentType, _ b: ComponentType) -> ComponentType {
		a + t * (b - a)
	}

	static func grad(_ hash: Int, _ x: ComponentType, _ y: ComponentType) -> ComponentType {
		let h = hash & 7
		let u = h < 4 ? x : y
		let v = h < 4 ? y : x
		return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
	}

	static func noise(x: ComponentType, y: ComponentType, seed: Int) -> ComponentType {
		let X = Int(floor(x)) & 255
		let Y = Int(floor(y)) & 255

		let xf = x - floor(x)
		let yf = y - floor(y)

		let u = fade(xf)
		let v = fade(yf)

		let perm = permutation.map { ($0 + seed) & 255 }

		let aa = perm[perm[X] + Y]
		let ab = perm[perm[X] + Y + 1]
		let ba = perm[perm[X + 1] + Y]
		let bb = perm[perm[X + 1] + Y + 1]

		let x1 = lerp(u, grad(aa, xf, yf), grad(ba, xf - 1, yf))
		let x2 = lerp(u, grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1))

		let result = lerp(v, x1, x2)
		return (result + 1) / 2  // normalize to [0,1]
	}
}

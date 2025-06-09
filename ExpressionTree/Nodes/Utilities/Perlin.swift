//
//  Perlin.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import Foundation
import simd

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

	static func noise(at coord: SIMD2<ComponentType>, seed: Int) -> ComponentType {
		let perm = permutation
		let offset = seed & 255

		// Grid coordinates
		let cell = floor(coord)
		let xi = Int(cell.x) & 255
		let yi = Int(cell.y) & 255

		// Local coordinates within cell
		let frac = coord - cell

		// Fade curves
		let u = fade(frac.x)
		let v = fade(frac.y)

		// Hash coordinates of the 4 square corners
		let aa = perm[(perm[(xi + offset) & 255] + yi) & 255]
		let ab = perm[(perm[(xi + offset) & 255] + yi + 1) & 255]
		let ba = perm[(perm[(xi + 1 + offset) & 255] + yi) & 255]
		let bb = perm[(perm[(xi + 1 + offset) & 255] + yi + 1) & 255]

		// Gradient results for each corner
		let x1 = lerp(u, grad(aa, frac.x, frac.y), grad(ba, frac.x - 1, frac.y))
		let x2 = lerp(u, grad(ab, frac.x, frac.y - 1), grad(bb, frac.x - 1, frac.y - 1))

		// Final interpolated result
		return (lerp(v, x1, x2) + 1) / 2
	}
}

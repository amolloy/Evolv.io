//
//  Perlin.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//
//  The noise math itself (fade/lerp/grad/noise) now lives only in MSL --
//  see mslPerlinPreamble() in MSLCodegen.swift, which formats this table
//  as a literal array so every noise node's generated kernel shares the
//  exact same randomized permutation for the life of the process, matching
//  what this table always guaranteed for the (now-removed) Swift noise path.
//

struct Perlin {
	static let permutation: [Int] = (0...255).shuffled() + (0...255).shuffled()
}

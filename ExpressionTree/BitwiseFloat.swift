//
//  BitwiseFloat.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/9/25.
//

import simd

public protocol BitwiseFloat {
	associatedtype RawBits: FixedWidthInteger & SIMDScalar

	static func toBits(_ value: Self) -> RawBits
	static func fromBits(_ bits: RawBits) -> Self
}

extension Float: BitwiseFloat {
	public typealias RawBits = UInt32

	public static func toBits(_ value: Float) -> UInt32 {
		value.bitPattern
	}

	public static func fromBits(_ bits: UInt32) -> Float {
		Float(bitPattern: bits)
	}
}

extension Double: BitwiseFloat {
	public typealias RawBits = UInt64

	public static func toBits(_ value: Double) -> UInt64 {
		value.bitPattern
	}

	public static func fromBits(_ bits: UInt64) -> Double {
		Double(bitPattern: bits)
	}
}

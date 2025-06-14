//
//  Tree.swift
//  Tree
//
//  Created by Andy Molloy on 6/8/25.
//

import Foundation
import CoreImage
import simd

public typealias ComponentType = Double
public typealias Value = SIMD3<ComponentType>
public typealias Coordinate = SIMD2<ComponentType>

extension Value {
	func averageLuminance() -> ComponentType {
		return (self.x + self.y + self.z) / 3.0
	}
}

public func simd_normalize(safe vector: Value) -> Value? {
	let length = simd_length(vector)
	if length < 1e-9 { // Use a small epsilon for floating point comparison
		return nil
	}
	return vector / length
}

internal let epsilon: ComponentType = 1e-9

extension SIMD3 where Scalar == ComponentType {
	/// Returns a new vector by replacing any non-finite values (NaN, infinity).
	/// - NaN values are replaced with 0.0.
	/// - Positive infinity is replaced with 1.0.
	/// - Negative infinity is replaced with -1.0.
	public func sanitized() -> SIMD3<ComponentType> {
		var newX = self.x
		if newX.isNaN {
			newX = 0.0
		} else if newX.isInfinite {
			newX = newX > 0 ? 1.0 : -1.0
		}

		var newY = self.y
		if newY.isNaN {
			newY = 0.0
		} else if newY.isInfinite {
			newY = newY > 0 ? 1.0 : -1.0
		}

		var newZ = self.z
		if newZ.isNaN {
			newZ = 0.0
		} else if newZ.isInfinite {
			newZ = newZ > 0 ? 1.0 : -1.0
		}

		return SIMD3<Double>(newX, newY, newZ)
	}
}

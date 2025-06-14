//
//  LightMapResult.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/14/25.
//

import simd

class LightMapResult: ExpressionResult {
	let source: ExpressionResult
	let dirX: ExpressionResult
	let dirY: ExpressionResult
	let delta: ExpressionResult
	let heightFactor: ExpressionResult
	let lightZ: ExpressionResult
	let color: ExpressionResult

	init(source: ExpressionResult,
		 dirX: ExpressionResult,
		 dirY: ExpressionResult,
		 delta: ExpressionResult,
		 heightFactor: ExpressionResult,
		 lightZ: ExpressionResult,
		 color: ExpressionResult = ConstantResult(1.0)) {
		self.source = source
		self.dirX = dirX
		self.dirY = dirY
		self.delta = delta
		self.heightFactor = heightFactor
		self.lightZ = lightZ
		self.color = color
	}
	
	func value(at coord: Coordinate) -> Value {
		let lightDirXSource = dirX.value(at: coord)
		let lightDirYSource = dirY.value(at: coord)
		
		let delta = self.delta.value(at: coord).averageLuminance()
		let heightFactor = self.heightFactor.value(at: coord).averageLuminance()
		let lightZ = self.lightZ.value(at: coord).averageLuminance()
		
		let height_x1 = source.value(at: coord + Coordinate(delta, 0)).averageLuminance()
		let height_x2 = source.value(at: coord - Coordinate(delta, 0)).averageLuminance()
		let Gx = height_x1 - height_x2
		
		let height_y1 = source.value(at: coord + Coordinate(0, delta)).averageLuminance()
		let height_y2 = source.value(at: coord - Coordinate(0, delta)).averageLuminance()
		let Gy = height_y1 - height_y2
		
		let surfaceNormal = Value(-Gx, -Gy, 1.0 / heightFactor)
		
		var lightDx = lightDirXSource.averageLuminance()
		var lightDy = lightDirYSource.averageLuminance()
		
		if lightDx < 0.0006 && lightDy < 0.0006 {
			lightDx = -0.5
			lightDy = 0.5
		}
		
		let lightDirection = Value(lightDx, lightDy, lightZ)
		
		guard let normal_normalized = simd_normalize(safe: surfaceNormal),
			  let light_normalized = simd_normalize(safe: lightDirection) else {
			return Value(repeating: 0.5)
		}
		
		let dotProduct = dot(normal_normalized, light_normalized)
		let finalValue = simd_clamp((dotProduct + 1.0) * 0.5, 0.0, 1.0)
		
		return color.value(at: coord) * finalValue
	}
}

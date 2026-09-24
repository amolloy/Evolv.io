//
//  DSLSampleDefinitions.swift
//  Evolv.io
//
//  The two node definitions from the "readable DSL for node authoring"
//  spike (see DSLCodegenNode.swift), kept in one place so NodeRegistry's
//  live "dsl-mod"/"dsl-color-grad" registrations and
//  DSLSpikeTests' parity checks can't drift apart by editing one copy of
//  the source text and not the other.
//
//  Registered under "dsl-"-prefixed names (not "mod"/"color-grad" --
//  those stay the hand-written production nodes) purely so both versions
//  can be picked from ContentView's sample list side by side. Nothing
//  here is meant to survive a decision on whether to pursue the DSL
//  further; see DSLCodegenNode.swift's header for what's deliberately not
//  done yet (NodeRegistry integration is real now, but there's still no
//  file loading, no hot reload, and no fix for Node.name's static-vs-
//  per-instance tension beyond this spike's placeholder).
//

enum DSLSampleDefinitions {
	static let modSource = """
	node "mod"(v0, v1) {
		let isZeroMask: bool3 = v1 == float3(0.0)
		let safeDivisor = select(v1, float3(1.0), isZeroMask)
		let remainder = fmod(v0, safeDivisor)
		let isNegativeRemainder: bool3 = remainder < float3(0.0)
		return select(remainder, remainder + v1, isNegativeRemainder)
	}
	"""

	// Same shape as ColorGradient._emitMSL (ExpressionTree/Nodes/ColorGradient.swift):
	// source is a sampled-function child, delta/heightFactor/lightZ/tapCount
	// are $params standing in for ColorGradient's live-tunable debug statics
	// (see colorGradParams below), and the per-tap finite-difference loop is
	// expressed as an `average(...)` reduction instead of Swift-side unrolling.
	static let colorGradSource = """
	node "color-grad"(source: fn, p1, p2, color, p3) requires(lighting) {
		let p1Val: float = avgLum(p1)
		let deltaLocal: float = (abs(p1Val) / 3.1) * $delta

		let p3Val: float = avgLum(p3)
		let heightFactor: float = p3Val * $heightFactor
		let lightZ: float = p3Val * $lightZ

		let angle: float = avgLum(p2)

		let gx = average(i in 1...$tapCount) {
			let radius: float = deltaLocal * (float(i) / float($tapCount))
			source(coord - float2(radius, 0.0)) - source(coord + float2(radius, 0.0))
		}
		let gy = average(i in 1...$tapCount) {
			let radius: float = deltaLocal * (float(i) / float($tapCount))
			source(coord - float2(0.0, radius)) - source(coord + float2(0.0, radius))
		}

		let lightDx: float = cos(angle)
		let lightDy: float = sin(angle)
		let lightDir = float3(lightDx, lightDy, lightZ)
		let lightLen: float = length(lightDir)
		let lightNormalized = lightDir / lightLen

		let lightMap = (lightLen < 1e-9) ? float3(0.5) : float3(colorGradChannel(gx.x, gy.x, heightFactor, lightNormalized, color.x), colorGradChannel(gx.y, gy.y, heightFactor, lightNormalized, color.y), colorGradChannel(gx.z, gy.z, heightFactor, lightNormalized, color.z))

		return signedPow(lightMap, p3Val)
	}
	"""

	/// Matches ColorGradient's current debugDelta/debugHeightFactor/
	/// debugLightZ/debugTapCount defaults -- not wired to
	/// ColorGradientDebugView's sliders (that integration is future work,
	/// only relevant if the DSL is pursued past spike status).
	static let colorGradParams: [String: DSLParamValue] = [
		"delta": .float(0.01),
		"heightFactor": .float(20.0),
		"lightZ": .float(0.0),
		"tapCount": .int(4),
	]

	static let modTemplate: DSLTemplate = parseOrFatalError(modSource, label: "modSource")
	static let colorGradTemplate: DSLTemplate = parseOrFatalError(colorGradSource, label: "colorGradSource")

	// A parse failure here means the embedded source text itself is broken,
	// not anything a caller passed in -- same "unrecoverable, not worth a
	// throwing API" reasoning as MetalRenderContext's device-unavailable
	// fatalError elsewhere in this module.
	private static func parseOrFatalError(_ source: String, label: String) -> DSLTemplate {
		do {
			return try DSLParser(source).parseTemplate()
		} catch {
			fatalError("DSLSampleDefinitions.\(label) failed to parse: \(error)")
		}
	}
}

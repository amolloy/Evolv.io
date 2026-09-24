//
//  DSLSampleDefinitions.swift
//  Evolv.io
//
//  Standalone Swift-embedded copies of the "mod"/"color-grad" node
//  definitions, kept separate from the real, live
//  Evolv.io/Resources/BundledNodes/{mod,color-grad}.evolvnode files so
//  DSLSpikeTests' parity checks don't depend on bundle-resource-copying
//  working correctly on the test target -- see that struct's header for
//  the full reasoning. Not registered anywhere; these templates are only
//  ever constructed directly in tests.

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

	// source is a sampled-function child; delta/heightFactor/lightZ/tapCount
	// are $params (see colorGradParams below) rather than baked literals,
	// so this embedded copy can be exercised with the same values the real
	// bundled file hardcodes without duplicating them as literal text.
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

	/// Matches the literals baked into the real
	/// Evolv.io/Resources/BundledNodes/color-grad.evolvnode file
	/// (0.01/20.0/0.0/4).
	static let colorGradParams: [String: DSLParamValue] = [
		"delta": .float(0.01),
		"heightFactor": .float(20.0),
		"lightZ": .float(0.0),
		"tapCount": .int(4),
	]

	// `colorGradSource`'s `requires(lighting)` resolves against the
	// reserved "lighting" intrinsic (see DSLCodegenNode._emitMSL) -- no
	// module to supply here. "lighting" used to be a real scanned module,
	// but a tree combining a DSL node requiring it with a hand-written
	// node that also needs lighting helpers (e.g. Figure 10: bump +
	// color-grad) got two separate text definitions of the same three
	// function names spliced into one kernel -- a real
	// "redefinition of 'avgLum'" Metal compile error. Routing through the
	// same intrinsic every hand-written lighting node already uses
	// guarantees there's only ever one definition.

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

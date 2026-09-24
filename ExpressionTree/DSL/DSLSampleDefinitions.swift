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

	/// `colorGradSource`'s `requires(lighting)` needs a real module to
	/// resolve against now that "lighting" isn't a hardcoded intrinsic
	/// (see DSLCodegenNode._emitMSL) -- same content as the bundled
	/// Evolv.io/Resources/BundledNodes/lighting.evolvnode, kept separate
	/// for the same test-isolation reason `modSource`/`colorGradSource`
	/// aren't shared with the bundled files (see the file header above).
	static let lightingModuleSource = """
	module "lighting" {
		func avgLum(v: float3) -> float {
			return (v.x + v.y + v.z) / 3.0
		}

		func colorGradChannel(gx: float, gy: float, heightFactor: float, lightNormalized: float3, colorTint: float) -> float {
			let normal = float3(-gx, -gy, 1.0 / heightFactor)
			let normalLen: float = length(normal)
			let t: float = dot(normal / normalLen, lightNormalized)
			return (normalLen < 1e-9) ? 0.5 : colorTint * t
		}

		func signedPow(v: float3, p: float) -> float3 {
			let s = select(float3(1.0), float3(-1.0), v < float3(0.0))
			return s * pow(abs(v), p)
		}
	}
	"""

	static let modTemplate: DSLTemplate = parseOrFatalError(modSource, label: "modSource")
	static let colorGradTemplate: DSLTemplate = parseOrFatalError(colorGradSource, label: "colorGradSource")
	static let lightingModule: DSLModule = {
		do {
			guard case .module(let module) = try DSLParser(lightingModuleSource).parseFile() else {
				fatalError("DSLSampleDefinitions.lightingModuleSource did not parse as a module")
			}
			return module
		} catch {
			fatalError("DSLSampleDefinitions.lightingModuleSource failed to parse: \(error)")
		}
	}()

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

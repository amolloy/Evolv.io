//
//  MSLCodegen.swift
//  Evolv.io
//
//  Core types for compiling a `Node` tree to a Metal Shading Language
//  expression. See the "Replace the Swift per-pixel evaluator with Metal
//  codegen" plan for the full migration this is phase A of.
//

/// A reference to an already-emitted MSL local variable holding a `float3`.
public struct MSLValue {
	public let variableName: String
}

/// Optional GPU-side resources a generated kernel may need bound alongside
/// its per-tree Params buffer (the shared Perlin permutation table, the
/// ColorGradient live-tunable uniforms, etc). Nodes that need one call
/// `context.require(...)` from within `_emitMSL`.
public struct MSLResourceRequirements: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }

	public static let perlinTable = MSLResourceRequirements(rawValue: 1 << 0)
	public static let colorGradientTunables = MSLResourceRequirements(rawValue: 1 << 1)
}

/// Accumulates emitted MSL statements while walking a `Node` tree once
/// (codegen happens a single time per distinct tree shape, not per pixel --
/// the resulting text becomes a compiled kernel that runs per pixel on the
/// GPU). Dedups by node identity so a node reached more than once emits its
/// expression only once; see `Node.codegenMSL(into:)`.
public final class MSLCodegenContext {
	private var statements: [String] = []
	private var memo: [ObjectIdentifier: MSLValue] = [:]
	private var nextVariableIndex = 0
	public private(set) var resourceRequirements: MSLResourceRequirements = []

	public init() {}

	/// Returns the memoized value for `key` if this node has already been
	/// emitted; otherwise calls `build` to get its MSL expression text,
	/// declares it as a fresh local variable, memoizes, and returns it.
	public func emit(for key: ObjectIdentifier, _ build: () -> String) -> MSLValue {
		if let cached = memo[key] {
			return cached
		}
		let value = declare(build())
		memo[key] = value
		return value
	}

	/// Emits a fresh `<type> tNN = expression;` statement and returns a
	/// reference to it. Exposed for sub-expressions that aren't themselves a
	/// distinct `Node` (and so have nothing to key a memo on) but still
	/// benefit from being pulled out into their own named statement -- e.g.
	/// an intermediate `bool3` mask in a multi-step node like `Mod`. Defaults
	/// to `float3` since that's what most intermediates are.
	@discardableResult
	public func declare(_ expression: String, type: String = "float3") -> MSLValue {
		let name = "t\(nextVariableIndex)"
		nextVariableIndex += 1
		statements.append("\(type) \(name) = \(expression);")
		return MSLValue(variableName: name)
	}

	public func require(_ requirement: MSLResourceRequirements) {
		resourceRequirements.insert(requirement)
	}

	/// All emitted statements so far, joined for splicing into a function body.
	public func body() -> String {
		statements.joined(separator: "\n\t")
	}
}

/// Formats a CPU-side `ComponentType` (Double) as an MSL float literal.
/// GPU math is float32 throughout (see the plan's precision-policy note), so
/// this doesn't need to preserve full Double precision -- just enough for
/// Swift's default `String(Double)` round-trip to read back sanely in MSL.
public func mslFloatLiteral(_ value: ComponentType) -> String {
	if value.isNaN { return "NAN" }
	if value.isInfinite { return value > 0 ? "INFINITY" : "-INFINITY" }
	return String(value)
}

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
/// its per-tree Params buffer. Only the Perlin permutation table is left --
/// its live-shuffled data can never be a `.evolvnode` text file (see
/// `NodeRegistry`'s `perlin` reserved-intrinsic note) -- everything else
/// that used to live here (`colorGradientTunables`, `lightingHelpers`) was
/// retired once its last hand-written Swift caller moved to a DSL
/// `requires(...)` module instead (see `lighting.evolvnode`). Nodes that
/// need this call `context.require(.perlinTable)` from within `_emitMSL`.
public struct MSLResourceRequirements: OptionSet, Sendable {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }

	public static let perlinTable = MSLResourceRequirements(rawValue: 1 << 0)
}

/// Accumulates emitted MSL statements while walking a `Node` tree once
/// (codegen happens a single time per distinct tree shape, not per pixel --
/// the resulting text becomes a compiled kernel that runs per pixel on the
/// GPU). Dedups by node identity so a node reached more than once emits its
/// expression only once; see `Node.codegenMSL(into:)`.
public final class MSLCodegenContext {
	private var statements: [String] = []
	private var memo: [ObjectIdentifier: MSLValue] = [:]
	// Nodes built synthetically inside another node's _emitMSL (e.g.
	// GradientDirection's `PreventZero([children[1], Constant(-0.5)])`) have
	// no other owner -- nothing keeps them alive past the `codegenMSL` call
	// that memoizes them. Swift can and does reuse a just-deallocated
	// object's memory address for the very next allocation, which gives the
	// new object the SAME ObjectIdentifier and makes it collide with the
	// old one's memo entry -- confirmed in practice: GradientDirection's
	// dirY (a second, distinct PreventZero) was silently returning dirX's
	// memoized result. Retaining every memoized node for the context's
	// lifetime keeps its address from being recycled during this walk.
	private var retainedNodes: [any Node] = []
	private var nextVariableIndex = 0
	public private(set) var resourceRequirements: MSLResourceRequirements = []
	// Open-ended counterpart to `resourceRequirements` above: named MSL
	// text blobs a DSL-defined node's `requires(name)` pulled in (see
	// DSLCodegenNode._emitMSL / DSLLibrary.swift), keyed by name so the
	// same module required by two different nodes in one tree is only
	// spliced into the kernel once. `resourceRequirements` stays a separate,
	// fixed OptionSet purely for the Perlin table intrinsic (never text,
	// see above); this is for everything else.
	private var customModuleTexts: [String: String] = [:]

	// Shared across a context and every sub-context `emitFunction` creates
	// (at any nesting depth), so generated function names are unique across
	// the *whole* codegen pass, not just within one context. Each
	// MSLCodegenContext used to get its own counter starting at 0, which
	// meant a color-grad nested inside another color-grad's source (exactly
	// Figure 9's shape: the outer color-grad's source itself contains the
	// inner color-grad) produced two functions both named "fn0" -- a
	// duplicate-definition compile error that made the whole tree's render
	// silently fall back to black. A reference type because Swift structs
	// can't be "the same mutable counter" shared across independently
	// constructed contexts; a class instance can be.
	private final class FunctionNameCounter {
		var next = 0
	}
	private let functionNameCounter: FunctionNameCounter

	public init() {
		functionNameCounter = FunctionNameCounter()
	}

	private init(sharingFunctionNamesWith parent: MSLCodegenContext) {
		functionNameCounter = parent.functionNameCounter
	}

	/// Returns the memoized value for `node` if it's already been emitted;
	/// otherwise calls `build` to get its MSL expression text, declares it
	/// as a fresh local variable, memoizes, and returns it.
	public func emit(for node: any Node, _ build: () -> String) -> MSLValue {
		let key = node.id
		if let cached = memo[key] {
			return cached
		}
		retainedNodes.append(node)
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

	/// Registers `text` (a module's already-generated MSL function
	/// definitions) under `name`, deduped so requiring the same module
	/// twice in one tree only splices it in once.
	public func requireModule(name: String, text: String) {
		customModuleTexts[name] = text
	}

	/// Every custom module required so far, in a deterministic order.
	public func customModulesMSL() -> String {
		customModuleTexts.keys.sorted().map { customModuleTexts[$0]! }.joined(separator: "\n\n")
	}

	private var extraFunctions: [String] = []

	/// Emits `node` as a standalone top-level MSL function taking its own
	/// `float2 coord` parameter, rather than inline-declaring it against the
	/// ambient coordinate, and returns the function's name so callers can
	/// invoke it at arbitrary coordinate expressions (e.g.
	/// `fn0(coord + float2(delta, 0.0))`). MSL functions can't be nested or
	/// close over enclosing locals, so this walks `node` in a fresh
	/// sub-context and splices the result in as its own function -- used by
	/// nodes that need to sample a subtree at coordinates other than the
	/// ambient one, like `LightMapResult`'s finite-difference taps.
	///
	/// Every generated function (this one and the outermost `evalTree`) uses
	/// the same parameter name, `coord` -- that's what lets a node's
	/// `_emitMSL` reference `"coord.x"` literally and have it resolve
	/// correctly regardless of which function it ends up spliced into,
	/// without threading a coordinate-variable-name through every node.
	public func emitFunction(for node: any Node) -> String {
		let name = "fn\(functionNameCounter.next)"
		functionNameCounter.next += 1

		let subContext = MSLCodegenContext(sharingFunctionNamesWith: self)
		let result = node.codegenMSL(into: subContext)
		resourceRequirements.formUnion(subContext.resourceRequirements)
		customModuleTexts.merge(subContext.customModuleTexts) { existing, _ in existing }

		// Nested functions this subtree needed must be defined before this
		// wrapper (which calls them), so bubble them up first.
		extraFunctions.append(contentsOf: subContext.extraFunctions)
		extraFunctions.append("""
		inline float3 \(name)(float2 coord) {
			\(subContext.body())
			return \(result.variableName);
		}
		""")
		return name
	}

	/// All emitted statements so far, joined for splicing into a function body.
	public func body() -> String {
		statements.joined(separator: "\n\t")
	}

	/// Every standalone function emitted via `emitFunction`, in dependency
	/// order, joined for splicing before the main kernel body.
	public func allFunctions() -> String {
		extraFunctions.joined(separator: "\n\n")
	}
}

/// The Perlin noise helper functions and permutation-table declaration,
/// prepended to generated kernel source whenever any node requires
/// `.perlinTable`. Reuses the existing Swift-side `Perlin.permutation`
/// table directly (formatted as an MSL literal array) so noise stays
/// byte-identical to today's CPU path during Phase A of the Metal codegen
/// migration -- only the fade/lerp/grad math itself runs at float32
/// instead of float64, not the table values.
func mslPerlinPreamble() -> String {
	let tableValues = Perlin.permutation.map { String($0) }.joined(separator: ", ")
	return """
	constant int kPerlinTable[512] = { \(tableValues) };

	inline float perlinFade(float t) {
		return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
	}

	inline float perlinLerp(float t, float a, float b) {
		return a + t * (b - a);
	}

	inline float perlinGrad(int hash, float x, float y) {
		int h = hash & 7;
		float u = h < 4 ? x : y;
		float v = h < 4 ? y : x;
		return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
	}

	inline float perlinNoise(float2 coord, int inOffset) {
		int offset = inOffset & 255;

		float2 cell = floor(coord);
		int xi = int(cell.x) & 255;
		int yi = int(cell.y) & 255;

		float2 frac = coord - cell;

		float u = perlinFade(frac.x);
		float v = perlinFade(frac.y);

		int aa = kPerlinTable[(kPerlinTable[(xi + offset) & 255] + yi) & 255];
		int ab = kPerlinTable[(kPerlinTable[(xi + offset) & 255] + yi + 1) & 255];
		int ba = kPerlinTable[(kPerlinTable[(xi + 1 + offset) & 255] + yi) & 255];
		int bb = kPerlinTable[(kPerlinTable[(xi + 1 + offset) & 255] + yi + 1) & 255];

		float x1 = perlinLerp(u, perlinGrad(aa, frac.x, frac.y), perlinGrad(ba, frac.x - 1.0, frac.y));
		float x2 = perlinLerp(u, perlinGrad(ab, frac.x, frac.y - 1.0), perlinGrad(bb, frac.x - 1.0, frac.y - 1.0));

		return (perlinLerp(v, x1, x2) + 1.0) / 2.0;
	}
	"""
}

/// Assembles the shared preamble (Perlin table, any DSL `requires(...)`
/// module text, any `emitFunction`-produced standalone functions) that goes
/// before a generated kernel's own per-tree function body -- shared by
/// `MSLTreeEvaluator` (parity testing) and `MetalRenderContext` (production
/// rendering) so the two don't drift.
func mslSharedPreamble(functions: String, resourceRequirements: MSLResourceRequirements, customModules: String = "") -> String {
	var preamble = ""
	if resourceRequirements.contains(.perlinTable) {
		preamble += mslPerlinPreamble() + "\n\n"
	}
	if !customModules.isEmpty {
		preamble += customModules + "\n\n"
	}
	if !functions.isEmpty {
		preamble += functions + "\n\n"
	}
	return preamble
}

/// Replicates `SIMD3.sanitized()` (Tree.swift): NaN -> 0, +/-infinity -> +/-1.
/// Applied per supersample before accumulating, matching NodeRenderer's
/// existing CPU behavior.
func mslSanitizeFunction() -> String {
	"""
	inline float3 sanitize(float3 v) {
		float3 r = v;
		for (int i = 0; i < 3; i++) {
			if (isnan(r[i])) r[i] = 0.0;
			else if (isinf(r[i])) r[i] = r[i] > 0.0 ? 1.0 : -1.0;
		}
		return r;
	}
	"""
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

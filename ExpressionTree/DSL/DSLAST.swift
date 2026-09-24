//
//  DSLAST.swift
//  Evolv.io
//
//  Spike: the parsed form of a node definition, before DSLCodegenNode
//  interprets it against an MSLCodegenContext. See DSLLexer.swift for why
//  this exists and DSLCodegenNode.swift for how it's actually run.
//

indirect enum DSLExpr {
	/// Raw numeric literal text, passed through to MSL verbatim (e.g. the
	/// user writes "1.0" or "1e-9" exactly as it should appear in MSL).
	case number(String)
	/// A bound name -- a child parameter, a `let`, a reduction loop
	/// variable, or (when called) an unbound passthrough to an MSL
	/// builtin/helper name like `select` or `avgLum`.
	case identifier(String)
	/// A `$name` reference, resolved against the params dictionary
	/// DSLCodegenNode is constructed with (the DSL's equivalent of today's
	/// `ColorGradient.debugDelta`-style live-tunable statics).
	case param(String)
	case unary(op: String, operand: DSLExpr)
	case binary(op: String, lhs: DSLExpr, rhs: DSLExpr)
	case ternary(cond: DSLExpr, then: DSLExpr, else_: DSLExpr)
	case call(callee: DSLExpr, args: [DSLExpr])
	case member(base: DSLExpr, name: String)
	/// `average(i in lo...hi) { <lets>* <trailingExpr> }` -- replaces
	/// ColorGradient's Swift-side unrolled tap loop. `lo`/`hi` must resolve
	/// to concrete integers at codegen time (an int literal or an int
	/// `$param`), since this unrolls `body` once per iteration rather than
	/// emitting a runtime MSL loop.
	case reduce(variable: String, lo: DSLExpr, hi: DSLExpr, body: [DSLLetStmt], result: DSLExpr)
}

struct DSLLetStmt {
	let name: String
	/// MSL type for the declared local, e.g. "bool3" -- defaults to
	/// "float3" (matching MSLCodegenContext.declare's default) when omitted.
	let type: String?
	let value: DSLExpr
}

struct DSLParam {
	let name: String
	/// True for a child sampled at arbitrary coordinates via
	/// MSLCodegenContext.emitFunction (e.g. ColorGradient's `source`) rather
	/// than emitted once against the ambient coordinate.
	let isFunction: Bool
}

// Public because DSLCodegenNode's initializer (called from outside this
// module, e.g. by tests via @testable import or eventually by whatever
// loads DSL source files) takes a DSLTemplate directly. Their own fields
// stay internal -- nothing outside this module needs to pick a DSLTemplate
// apart, only to hand one to DSLCodegenNode.
public struct DSLTemplate {
	let name: String
	let params: [DSLParam]
	/// Names a node's body wants resolved -- either the reserved "perlin"
	/// intrinsic (its table is live-shuffled Swift data, never a text file)
	/// or a module name resolved by whoever constructs the DSLCodegenNode
	/// (see DSLLibrary.scan's namespace-aware module resolution).
	let requires: [String]
	/// `param $name: type = <literal>` declarations -- a self-contained
	/// default for a `$name` reference, used when nothing external supplies
	/// one (see DSLCodegenNode._emitMSL's `effectiveParams` merge). Exists
	/// because a library-loaded node (unlike the two original
	/// DSLSampleDefinitions demos) has no Swift caller to inject params.
	let paramDefaults: [String: DSLParamValue]
	let body: [DSLLetStmt]
	let returnExpr: DSLExpr
}

public enum DSLParamValue {
	case float(ComponentType)
	case int(Int)
}

/// A `func name(p0: type, ...) -> type { <let>* return expr }` declaration,
/// only valid inside a `module` block -- see DSLModule.
struct DSLFuncDecl {
	let name: String
	let params: [(name: String, type: String)]
	let returnType: String
	let body: [DSLLetStmt]
	let returnExpr: DSLExpr
}

/// A `module "name" { func ... }` file -- a named bag of MSL helper
/// functions a node can pull in via `requires(name)`, resolved by
/// DSLLibrary the same way node names are (bare, or namespace-prefixed by
/// an enclosing `Package.evolvnode`). Public for the same reason
/// `DSLTemplate` is: it's a parameter type on DSLCodegenNode's public init.
public struct DSLModule {
	let name: String
	let funcs: [DSLFuncDecl]
}

/// A module resolved for one particular `requires()` clause -- pairs the
/// parsed module with the fully-qualified name it was actually registered
/// under (see `DSLLibrary.scan`'s namespace resolution). That qualified
/// name, not whatever bare text a `requires()` clause happened to write,
/// is what a name-mangled MSL prefix gets derived from (see
/// DSLCodegenNode's `mslModulePrefix`) -- so two different modules that
/// both happen to be named "helpers" in two different packages still get
/// distinct prefixes and can never collide, however many of them (or the
/// "perlin" intrinsic) end up required in one tree.
public struct DSLResolvedModule {
	let qualifiedName: String
	let module: DSLModule
}

/// What a single `.evolvnode` file turned out to contain -- exactly one of
/// these per file (mirrors the original "1:1 file:node" request, extended
/// to modules and package manifests).
enum DSLFile {
	case node(DSLTemplate)
	case module(DSLModule)
	case package(name: String)
}

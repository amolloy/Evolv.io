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
	/// Names matched against DSLCodegenNode._emitMSL's known requirement
	/// keywords ("lighting", "perlin") -- see MSLResourceRequirements.
	let requires: [String]
	let body: [DSLLetStmt]
	let returnExpr: DSLExpr
}

public enum DSLParamValue {
	case float(ComponentType)
	case int(Int)
}

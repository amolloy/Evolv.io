# The `.evolvnode` format

This is the text format every expression-tree operator (`+`, `mod`, `bump`,
`bw-noise`, ...) is defined in. A `.evolvnode` file is parsed once, compiled
to Metal Shading Language (MSL), and the resulting MSL is what actually runs
per pixel on the GPU — there's no interpreter running your node's logic at
render time.

The only things that *aren't* `.evolvnode` files are `Constant`/`ConstantTriplet`
(a bare number like `0.5` or a `#(r g b)` triplet — literal syntax the outer
Lisp-style parser recognizes directly, not a name+children shape) and the
Perlin permutation table (live-shuffled Swift data, exposed as a reserved
`perlin` intrinsic — see [Requires and modules](#requires-and-modules)).
Everything else, including every arithmetic operator, is a node like any
other and can be edited or replaced the same way.

Implementation, if you need to go deeper than this document:
`ExpressionTree/DSL/DSLLexer.swift` (tokenizer), `DSLParser.swift` (grammar),
`DSLAST.swift` (parsed shape), `DSLCodegenNode.swift` (interprets the parsed
shape into MSL), `DSLLibrary.swift` (scans folders, resolves namespacing).

## Where files live

- **Bundled** (shipped with the app): `Evolv.io/Resources/BundledNodes/*.evolvnode`,
  flat — Xcode's synchronized-group resource copying doesn't preserve
  subfolders, so this location is deliberately one level deep, no nesting.
  Drop a new file here and it's automatically part of the app the next time
  it's built — no project-file editing needed.
- **User-editable**: the app's own sandboxed container Documents folder
  (`~/Library/Containers/com.amolloy.Evolv-io/Data/Documents/Nodes/`),
  reachable via the app's **Reveal Nodes Folder** menu item. This one *is*
  scanned recursively, and supports the namespacing scheme below.
- After adding or editing a file, use the app's **Reload Custom Nodes** menu
  item to pick it up without relaunching — this re-scans both locations and
  clears the compiled-kernel cache (so an edited `module` file's new content
  actually takes effect, not just a stale compile of the old text).

A bad file (parse error, name collision, unresolved `requires`) is logged as
a load issue and skipped — it's never a crash, and it never silently
overrides another file's claim on a name. Issues print to the console
(`DSL load issue (<file>): <message>`), and each load also logs a
one-line summary of every node/module it *did* register successfully, so
"did my file actually load" is always answerable by checking the console
after "Reload Custom Nodes".

## The three file kinds

Each file is exactly one of:

```
node "name"(params...) [requires(...)] { body }
module "name" { func declarations }
package "name"
```

Almost everything you'll write is a `node`. `module` files hold shared MSL
helper functions a node can pull in (see [Requires and
modules](#requires-and-modules)). `package` is a one-line manifest file
(namespacing, described under [Loading and namespacing](#loading-and-namespacing))
— you'll rarely need it for the bundled folder.

## Anatomy of a node file

The simplest possible node:

```
node "+"(v0, v1) {
	return v0 + v1
}
```

- `"+"` is the name this node is invoked by from the outer Lisp-style
  expression syntax, e.g. `(+ x y)`. It can be any string, including
  operator-looking names like `+`/`*`/`/` — whatever you write in the quotes
  is looked up verbatim when a tree is parsed.
- `(v0, v1)` declares this node's **children** — the sub-expressions passed
  to it in the S-expression, in order. A node invoked as `(+ x y)` must
  declare exactly 2 params; a mismatch is a hard precondition failure at
  construction time, not a graceful error.
- Every child is a `float3` by convention — this whole system represents
  colors/values as RGB triplets, and a "scalar" is just a triplet with all
  three channels equal (a broadcast). There's no dedicated scalar type for
  children.
- The body is a sequence of `let`/`param` statements followed by exactly one
  `return <expr>`.
- Inside the body, `coord` is always available — the ambient pixel
  position (`float2`) being evaluated. Most nodes never need it directly
  (they just combine their children), but anything that samples at an
  *offset* coordinate (noise, finite-difference gradients) uses it — see
  `bw-noise.evolvnode`:

```
node "bw-noise"(e0, e1) requires(perlin) {
	let v0 = e0 * 50.0
	return float3(
		perlinNoise(coord * v0.x, int(e1.x)),
		perlinNoise(coord * v0.y, int(e1.y)),
		perlinNoise(coord * v0.z, int(e1.z))
	)
}
```

A node with zero children (a leaf, like `x`/`y`) just declares empty
parens:

```
node "x"() {
	return float3(coord.x)
}
```

## Types

Two families of "type" show up, and they mean different things:

- **MSL types**, written as plain identifiers (`float`, `float3`, `bool`,
  `bool3`, ...) — used on `let` statement type annotations (`let mask:
  bool3 = ...`) and `module` function signatures. A `let` with no
  annotation defaults to `float3`. These are just spliced verbatim into
  the generated MSL, so anything MSL itself accepts here is fair game.
- **`param` types**, restricted to exactly `float` or `int` — see `$param`
  below. `int` exists only for things that must be known at *codegen* time
  (an `average(...)` loop's bounds); `float` is everything else, including
  every `debug`-annotated value.

## Expressions

Standard C-like precedence, lowest to highest:

```
ternary  := or ('?' expr ':' expr)?
or       := and ('||' and)*
and      := bitAnd ('&&' bitAnd)*
bitAnd   := equality ('&' equality)*      -- bitwise, e.g. the "and" node's masking
equality := comparison (('=='|'!=') comparison)*
comparison := additive (('<'|'<='|'>'|'>=') additive)*
additive := multiplicative (('+'|'-') multiplicative)*
multiplicative := unary (('*'|'/') unary)*
unary    := ('-'|'!')? postfix
postfix  := primary ('.' IDENT | '(' args ')')*
primary  := NUMBER | IDENT | '$'IDENT | '(' expr ')' | average(...)
```

Member access (`.x`/`.xy`/`.rgb`, MSL swizzle syntax) and function calls
both work via postfix, so `select(v1, float3(1.0), isZeroMask)`,
`gx.x`, and `normalize(v).z` all parse as expected.

**Any identifier that isn't a known child/`let`/`$param` name is passed
through to the generated MSL verbatim**, whether referenced bare (a
constant like `M_PI_F`) or called (`select(...)`, `length(...)`,
`avgLum(...)`, `float3(...)`). There's no fixed whitelist of "allowed
builtins" — if MSL has a function or constant by that name, it just works.
The flip side: a genuine typo isn't caught by the DSL parser or by
"Reload Custom Nodes" succeeding — it only surfaces as a Metal compile
error the next time that specific node is actually rendered (logged to the
console as a render failure). `x < y<uint3>`-style generic-cast syntax
(`as_type<uint3>`) is also supported, folded into one identifier so it can
be called like any other passthrough name.

## `let` statements

```
let name = expr                  // type defaults to float3
let name: bool3 = v1 == float3(0.0)
```

Each `let` becomes one MSL local declaration, in the order written. Later
statements (including the final `return`) can reference any earlier
`let`'s name.

## `$param` and defaults

A `param` statement gives a `$name` reference a value:

```
param $delta: float = 0.02
```

- `$delta` is then usable anywhere in the body's expressions, substituted
  as a literal MSL numeric constant.
- The default (`0.02` here) is used whenever nothing else supplies a value
  for `$delta` — which, for every node loaded through the normal bundled/
  user-folder scanning path, is *always* (there's currently no mechanism
  for a tree to inject a different literal per call site; that's what
  ordinary children are for). Treat the default as the value, unless it
  also carries a `debug` clause (next section).
- `param` statements must appear before the body's `let`s/`return` are
  otherwise free-form — same top-level list as `let`, just filtered out of
  the emitted statement sequence.
- Only `float` and `int` are valid param types. `int` params exist
  specifically for `average(...)`'s loop bounds (see below) — anything
  else should be `float`.

## Debug hooks: live-tunable sliders and toggles

Any `float` param can carry an optional `debug` clause:

```
param $strength: float = 0.7 debug slider(0.0, 1.0)
param $showGrid: float = 1.0 debug toggle
```

This is how you get a knob in the app's debug view without hand-editing
the file and reloading for every guess. Mechanically:

- **It's a real live GPU uniform, not a baked literal, and not a
  recompile-on-change.** A `debug`-annotated `$param` reads from a small
  uniform buffer the compiled kernel already has bound; dragging a slider
  just writes a new float into that buffer and re-renders with the *same*
  compiled pipeline. Every other (non-`debug`) `$param` is still baked in
  as a plain MSL literal at compile time, exactly as before this existed.
- **`toggle` is just a `float` slider restricted to 0.0/1.0** — there's no
  separate bool param type. MSL treats any non-zero scalar as true in a
  condition, so use it directly: `$showGrid != 0.0 ? a : b`, or even bare
  in a ternary condition if your expression is already scalar.
- **One control per node *type* + param name, not per occurrence.** If
  `bump` appears three times in one tree, there's still exactly one
  `bump.strength` slider, and moving it retunes all three at once. This is
  deliberate: the point is finding the one correct constant for a node
  type (reverse-engineering Sims' original values), not independently
  tuning each call site. It also means every occurrence of a node type
  must already agree on that param's default — which they always do,
  since the default comes from the file, parsed once.
- **Only `float` params can carry `debug`** — the parser rejects it on
  `int`.
- **Where it shows up**: open the app, right-click the rendered image, and
  choose **Show Debug View** — this opens `NodeDebuggingView` for exactly
  that expression. Every `debug`-annotated param anywhere in that tree
  appears as a `Toggle` or `Slider`, labeled `<node-name>.<param-name>`
  (e.g. `bump.strength`). There's no separate registration step; declaring
  the clause in the file is the whole API.
- **Rendering without the debug view open** (the main canvas, tree-diagram
  thumbnails, etc.) always uses the in-file default — nothing changes for
  those call sites just because a param happens to be `debug`-annotated.

Real example, from `color-grad.evolvnode`:

```
node "color-grad"(source: fn, p1, p2, color, p3) requires(lighting) {
	param $debugDelta: float = 0.01 debug slider(0.0, 1.0)
	param $debugHeightFactor: float = 20.0 debug slider(0.0, 100.0)
	param $debugLightZ: float = 0.0 debug slider(0.0, 2.0)

	let p1Val: float = avgLum(p1)
	let deltaLocal: float = (abs(p1Val) / 3.1) * $debugDelta
	...
}
```

## Sampled children (`:fn` params)

A child param can be declared two ways:

```
node "color-grad"(source: fn, p1, p2, color, p3) ...
```

- **Plain** (`p1`, `p2`, `color`, `p3` above): evaluated once, against the
  ambient `coord`, before the node's own body runs — you just use it as an
  ordinary `float3` value.
- **`: fn`** (`source` above): *not* evaluated up front. Instead you get to
  call it like a function, at whatever coordinate you want:
  `source(coord - float2(radius, 0.0))`. This is how finite-difference
  gradients and multi-tap filters work — `color-grad`/`bump`/
  `grad-direction`/`color-grad-curvature` all sample their `source` child
  at several nearby offsets and combine the results. Under the hood this
  compiles the child subtree into its own standalone MSL function once;
  calling it twice at two different coordinates does not evaluate the
  child's tree twice from scratch in some naive sense, but it does mean
  two genuinely separate GPU function calls, so don't reach for `:fn`
  unless you actually need more than one sample.

## `requires(...)` and modules

A node's `requires(...)` clause lists module names (or the reserved
`perlin` intrinsic) whose helper functions it wants to call by plain name:

```
node "color-grad"(...) requires(lighting) {
	...
	let t: float = colorGradChannel(gx.x, gy.x, heightFactor, lightNormalized, color.x)
	...
}
```

`perlin` is special-cased: it's the only intrinsic left, because the
permutation table it uses is runtime-shuffled Swift data (`Perlin.swift`),
never something a text file could express. Requiring it makes
`perlinNoise(coord, offset)` available (and only that — no other Perlin
internals are exposed).

Everything else in a `requires(...)` list must be the name of a `module`
file, e.g. `lighting.evolvnode`:

```
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
}
```

Module `func`s have their own small grammar: typed params (`name: type`,
plain MSL types, no `fn` role, no `$param` support at all), a typed return,
and a body of `let`s + `return`. They can call each other by plain name.

Two things make this safe to mix-and-match arbitrarily:

- **Every module's functions get compiled under a name-mangled prefix**
  derived from the module's own fully-qualified name (see
  [Loading and namespacing](#loading-and-namespacing)), invisibly, so two
  unrelated modules that both happen to define `helper` — or the same
  module required by two different nodes in one tree — can never produce
  a duplicate-symbol compile error, however many end up combined in one
  render.
- **A missing module is a load issue, not a crash.** `requires(nonexistent)`
  gets logged and that one node is skipped; everything else still loads.

## `average(i in lo...hi) { ... }`

A reduction that unrolls at *compile* time (not a runtime GPU loop) into
`hi - lo + 1` independently-scoped copies of its body, averaging their
results:

```
let gx = average(i in 1...4) {
	let radius: float = deltaLocal * (float(i) / float(4))
	source(coord - float2(radius, 0.0)) - source(coord + float2(radius, 0.0))
}
```

- `lo`/`hi` must resolve to concrete integers at compile time — a plain
  integer literal, or an `int`-typed `$param` (never a `float` param, never
  a runtime value).
- `i` is available inside the block as a plain integer, usable in
  arithmetic (`float(i)`) but not as a `float3`.
- The block's last expression (no `return` keyword here — just a trailing
  expression, unlike a node/function body) is the per-iteration value;
  the whole `average(...)` expression evaluates to their mean.
- This is how any node needing a variable-density multi-tap filter (as
  opposed to a fixed handful of hardcoded offsets) should be written —
  it's the DSL's replacement for what used to be a hand-unrolled Swift
  loop with a `debugTapCount` static.

## Loading and namespacing

Both roots (bundled + user) are scanned the same way: every `.evolvnode`
file is parsed, then every `node`'s `requires()` and namespace are
resolved, in this order:

1. **Name collisions are rejected, not overridden.** The first successfully
   parsed file to claim a name (`Constant`/`ConstantTriplet`, or an earlier
   file in the same scan) wins; anything else claiming that name afterward
   is logged as a load issue and skipped entirely — including a second
   file that also happens to define e.g. `node "mod"`.
2. **Package namespacing** (user folder only — the bundled folder is flat,
   so this never applies there): a subfolder containing a file named
   exactly `Package.evolvnode` (content: just `package "somename"`)
   namespaces every node/module anywhere beneath that folder as
   `somename.<bare-name>` instead of the bare name — so a distributed pack
   of custom nodes can't collide with anything else in the user's folder.
   A deeper subfolder's own `Package.evolvnode` replaces the outer one for
   its own subtree rather than stacking (no `a.b.name`-style chains).
   Loose files with no enclosing `Package.evolvnode` register under their
   bare declared name.
3. **`requires(x)` resolves `x` against the requiring node's own namespace
   first, then falls back to an unnamespaced module named `x`.** This is
   what lets a namespaced node inside a package still say plain
   `requires(lighting)` and reach a plain, unnamespaged `lighting.evolvnode`
   if the package doesn't ship its own.

## Debugging a bad file

- **Nothing loads / a node is missing**: check the console after launch or
  "Reload Custom Nodes" for `DSL load issue (<file>): <message>` — usually
  a parse error (mismatched braces, wrong keyword) or a name collision.
- **The node loads but rendering it fails or produces black/garbage**:
  that's a Metal compile or runtime error in the *generated* MSL, most
  often from a typo in a passthrough identifier (an MSL function/constant
  name that doesn't actually exist) or a param-count mismatch with how the
  node's invoked. There's no separate DSL-level type checker — the DSL
  layer's job is producing syntactically valid MSL text; Metal itself is
  what ultimately validates it, one render at a time.
- **An edited `module` or node file doesn't seem to take effect**: make
  sure you hit "Reload Custom Nodes" — this is also what clears the
  compiled-kernel cache, since a tree's cache key doesn't encode a
  required module's *content*, only the calling node's own structure.

## Quick reference

| Want to... | Write... |
|---|---|
| Declare a node taking two children | `node "name"(v0, v1) { ... }` |
| Declare a leaf (no children) | `node "name"() { ... }` |
| Sample a child at an offset coordinate | `node "name"(source: fn) { ... source(coord + float2(dx, dy)) ... }` |
| Pull in shared helpers | `node "name"(...) requires(lighting) { ... }` |
| Define shared helpers | `module "name" { func f(v: float3) -> float3 { ... } }` |
| Give a tunable a self-contained default | `param $k: float = 0.5` |
| Make it a live slider | `param $k: float = 0.5 debug slider(0.0, 1.0)` |
| Make it a live toggle | `param $k: float = 1.0 debug toggle` |
| Multi-tap average, compile-time unrolled | `average(i in 1...4) { ... }` |
| Namespace a folder of custom nodes | drop a `package "name"` file named `Package.evolvnode` at its root |

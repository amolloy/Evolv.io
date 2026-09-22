# `bump` investigation log

Working notes on `bump`, in the same spirit as `ColorGradient.md`. `bump`
takes 8 args: `(source, dirX, dirY, color1, color2, lightZ, heightFactor,
delta)`. Structurally it's `grad-direction`/`color-grad`'s sibling --
finite-difference `source` into a height field, light it, blend
`color1`/`color2` (or tint) by the result -- but unlike `grad-direction`
(verified against fig. 4h) or `color-grad` (this whole other file's worth of
investigation), `bump` has never been independently checked against
anything. It appears exactly three times in known genotypes: once in
Figure 10, twice in Figure 12 (which we can't render yet -- blocked on
`warped-ifs`/`atan`/`vector`). Every judgment about it so far has been
indirect, filtered through those much larger surrounding trees.

## The original guess

`Bump.swift` delegates straight to `LightMapResult` -- the same machinery
`grad-direction` uses, with `clamp: true` (mix between `color1`/`color2`
rather than `color-grad`'s unclamped tint). `source`/`dirX`/`dirY` line up
1:1 with `grad-direction`'s `source`/`dirX`/`dirY`; `color1`/`color2` fill
the two-color-blend role `grad-direction` leaves at its defaults
(`0.0`/`1.0`); `lightZ`/`heightFactor`/`delta` are taken directly as given.
This was never stress-tested on its own -- it rode along unexamined until
the Figure 10 "columns instead of spikes" investigation pointed straight at
it.

## Timeline of attempts

### 1. Diagnosed via Figure 10: source-as-height-field can't produce texture here
Figure 10's only `bump` call is `(bump (if x 10.7 y) #(0.94 0.01 0.4) 0.78
#(0.18 0.28 0.58) #(0.4 0.92 0.58) 10.6 0.23 0.91)`. Traced the whole tree's
data flow and found that *every* branch feeding the outer `color-grad`
-- including this `bump` call -- ends up purely a function of `x`, with all
of Figure 10's `y`-dependence carried by a single bare `+ y` term much
higher in the tree. Root cause of `bump`'s piece of that: `source = (if x
10.7 y)` is a bare constant (`10.7`) on one side of `x=0` and a bare linear
coordinate (`y`) on the other -- and *any* implementation that
finite-differences `source` into a height field is structurally guaranteed
to see zero curvature from either branch (a constant has zero gradient; a
plane has zero curvature), for *any* `delta`/`heightFactor`. Not a tuning
problem -- geometry. This matches the observed "columns, not spikes"
symptom and doesn't depend on the specific parameter values at all.

### 2. Tried: replace source-differencing with an analytic radial dome [tried and reverted]
Hypothesis: `bump` (the name itself suggests a literal raised dome/spike,
and this codebase is already in the Perlin procedural-texture lineage) is
a closed-form dome centered at `(dirX, dirY)` -- collapsed to scalars via
`.averageLuminance()` -- with an analytic normal, independent of `source`
entirely. Implemented as `amplitude * (1 - (r/radius)^2)^2` (C1-smooth: flat
at the apex, flat at the rim), `heightFactor` as amplitude, `delta` as
radius, light simplified to `normalize(0, 0, lightZ)` (reasonable given
`lightZ=10.6` in the only renderable call already made the old light
direction ~99.6% vertical regardless of `dirX`/`dirY`).

**First pass kept the old source-finite-difference term additively on top of
the dome.** Rendered the bump stage alone: **just three flat vertical
bands** (narrow teal/green at the far edges, one wide blue band filling most
of the image) -- no visible dome at all, and no change to Figure 10's overall
render either.

**Diagnosed why**: reused the same `delta` (`0.91`) for both the kept
source-FD step and the dome radius. `0.91` is ~90% of the canvas half-width,
so the FD sample points `x±0.91` straddled `source`'s `if x` discontinuity
across nearly the *entire* canvas -- one sample landing on the `10.7`
branch, the other on `y` -- producing a huge, nearly-constant spurious
gradient (magnitude ~10) that swamped the dome's much smaller amplitude
(`0.23`) into irrelevance and saturated the normal into one fixed
orientation almost everywhere. That's exactly the three-band artifact:
not "no effect from the dome," but "the dome's effect present but ~40x too
small to see next to a bug." Dropped the source-FD term entirely in
response (shape from the dome alone) -- fixed the immediate artifact, but
we hadn't yet re-rendered to see if the dome alone looks right before the
next round of scrutiny below made us step back further.

### 3. Cross-checked the dome theory against Figure 12's two `bump` calls [analysis only -- Figure 12 isn't renderable yet]
Figure 12 has two `bump` calls that are clearly a duplicated/mutated pair
(share `dirX`, `dirY`, `color1`, `color2`, `heightFactor` exactly; differ
only in `source`, `lightZ`, `delta`):

| | `source` | `dirX` | `dirY` | `color1` | `color2` | `lightZ` | `heightFactor` | `delta` |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Fig 10** | `(if x 10.7 y)` | `#(0.94 0.01 0.4)` | `0.78` | `#(0.18 0.28 0.58)` | `#(0.4 0.92 0.58)` | `10.6` | `0.23` | `0.91` |
| **Fig 12 (a)** | `(+ (round x y) y)` | `#(0.46 0.82 0.65)` | `0.02` | `#(0.1 0.06 0.1)` | `#(0.99 0.06 0.41)` | `1.47` | `8.7` | `3.7` |
| **Fig 12 (b)** | `(warped-ifs ...)` | `#(0.46 0.82 0.65)` | `0.02` | `#(0.1 0.06 0.1)` | `#(0.99 0.06 0.41)` | `0.83` | `8.7` | `2.6` |

Two findings against the dome theory:

- **`dirX` is a 3-vector constant and `dirY` is a bare scalar constant in
  all three known calls, with no exception.** If they were symmetric roles
  (two components of one direction, or one position), you'd expect both to
  be the same shape. Consistently having one be a triplet and the other a
  scalar, across every known call, suggests they're not symmetric -- and
  collapsing `dirX` via `.averageLuminance()` (as both the old light-direction
  reading and the new dome-center reading do) throws that asymmetry away.
  A per-channel interpretation (three per-channel dome centers in X, sharing
  one Y from `dirY`) would use the data losslessly instead -- not tried.
- **`delta` (read as radius) is bigger than the entire canvas in both Figure
  12 calls** (`3.7`, `2.6`, vs. a canvas half-width of `1.0` -- and Figure
  10's `0.91` already nearly filled it). Under literal `radius = delta`,
  the dome's outer flat rim would never actually appear on-screen in *any*
  known call -- it would always render as an unbounded partial gradient/tilt,
  never a genuine bounded "spike." That undermines `radius = delta` as a
  mapping regardless of how Figure 10 alone looks. `radius = 1/delta` gives
  much more plausible bounded values across all three calls (`1.1`, `0.27`,
  `0.38`) -- proposed, not yet tried.
- Softer, secondary note: `heightFactor` (amplitude, in this theory) is
  `8.7` in both Figure 12 calls vs. `0.23` in Figure 10 -- a ~38x jump. Only
  meaningful to judge once the radius mapping above is sorted out, since
  right now that steepness has no bounded dome to be steep *within*.

### 4. Decision: revert to the original `LightMapResult`-based guess
The dome direction is motivated by a real, tuning-independent structural
finding (#1) -- but it hasn't produced a render the user found convincing,
Figure 12's argument shapes raised real doubts about the specific `radius`/
`dirX` mappings tried, and there wasn't much prior investment in the
original guess to begin with. Reverted `Bump.swift` to the original
`LightMapResult`-delegating implementation. Logging the dome attempt and
its open threads here, per `ColorGradient.md`'s practice, so this specific
direction isn't lost or re-derived from scratch later.

### 5. Realized #2/#3 were probably solving the wrong problem: the argument *positions* themselves look mis-mapped
User's observation: every other function with a direction-like pair
(`grad-direction`'s `dirX,dirY`; `color-grad`'s `p1,p2`) has that pair as
**two adjacent bare scalars**. `bump`'s positions 1-2 (`dirX,dirY` in the
current mapping) are a vector followed by a scalar -- not two scalars, and
not adjacent same-shaped values the way every other direction-like pair in
the whole corpus is. That's a much sharper problem than "feels asymmetric":
laying out the literal syntactic shape of every argument (excluding
`source`, always a nontrivial sub-expression in all three calls) across all
three known `bump` calls --

| position | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| current label | `dirX` | `dirY` | `color1` | `color2` | `lightZ` | `heightFactor` | `delta` |
| shape (all 3 calls) | vector | scalar | vector | vector | scalar | scalar | scalar |

-- position 2 is a scalar, but it's flanked by vectors on *both* sides
(positions 1 and 3). It has no scalar neighbor anywhere. It cannot be one
half of an adjacent-scalar pair no matter how the roles get relabeled --
that's fixed by the data, not an interpretation choice. The only place in
the whole 8-slot list where two scalars actually sit next to each other is
positions 5-6-7 (currently `lightZ`, `heightFactor`, `delta`). So if `bump`
has a `dirX`/`dirY`-style adjacent-scalar pair at all, matching the
convention every other function follows, it has to be two of *those*
three -- not positions 1-2.

Second, independent piece of evidence: `color-grad`'s proven shape is
`(source, [scalar, scalar], vector, scalar)` -- direction pair immediately
after `source`, then the color, then one trailing scalar. `Bump.swift`'s
original comment says its argument positions were ported 1:1 from
`grad-direction`'s `source/dirX/dirY` by analogy, never independently
checked. If `bump` actually followed `color-grad`'s proven template,
position 1 should be a scalar. It isn't, in any of the three calls.

**Consequence**: this isn't just a `dirX`/`dirY` naming problem, it
cascades. If the true `dirX`/`dirY` are two of positions 5/6/7, that leaves
position 1 (vector), position 2 (scalar), and whichever one of 5/6/7 isn't
`dirX`/`dirY` as **three slots with no identified role at all** -- not
"probably lightZ/heightFactor/delta as guessed," genuinely unknown. Both
the original `LightMapResult` guess (#0) and the analytic-dome attempt
(#2/#3) took positions 1-2 as `dirX`/`dirY` and were never able to be
right about that, independent of which lighting/shape model sits on top --
so neither result (three flat bands, or no visible change) should be read
as evidence about lighting/shape models at all; the input mapping under
both was already wrong. This is now the leading hypothesis, ahead of "which
lighting model" -- the argument order needs to be sorted out before any
lighting/shape theory can be fairly tested.

### 6. Tried: reordered mapping -- `source` as normal, colors/light moved to fit #5's shape constraints [implemented, unverified]
Proposal: `source` (position 1) is read directly as a normal vector -- no
finite-differencing at all, classic normal-mapping rather than
height-field bump-mapping -- combined with a reordering that finally
satisfies #5's shape constraints instead of fighting them:

| position | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| new label | `source`/normal | `multiplier` | `strength` | `color1` | `color2` | `dirX` | `dirY` | `lightHeight` |
| shape (all 3 calls) | sub-expr | vector | scalar | vector | vector | scalar | scalar | scalar |

This finally puts `color1`/`color2` on the only adjacent vector-vector pair
after `source`/`multiplier` (positions 4-5), and `dirX`/`dirY` on an
adjacent scalar-scalar pair drawn from positions 6/7/8 exactly as #5 said
it had to be, with `lightHeight` taking the remaining slot. `multiplier`
(position 2, vector) scales `source` component-wise before normalizing;
`strength` (position 3, scalar) blends between a flat `(0,0,1)` normal and
the (possibly degenerate) computed one -- a common real bump-mapping knob,
picked because it was the only slot with no evidence either way, not
because it's confirmed.

**Known flaw, checked against the two calls we can actually verify:**
Figure 10's `source = (if x 10.7 y)` and Figure 12(a)'s `source = (+ (round
x y) y)` are both pure scalar-broadcast expressions (`Value(v,v,v)` -- same
value in R/G/B, built from `x`/`y`/bare numbers with no per-channel-varying
operator anywhere in the subtree). `normalize(v,v,v)` is `±(1,1,1)/√3` for
any nonzero `v` -- a fixed direction, not a field. Multiplying by
`multiplier` before normalizing doesn't fix this: `normalize(0.94v, 0.01v,
0.4v) = sign(v) · normalize(0.94, 0.01, 0.4)`, still just a fixed direction
that flips sign, never a continuous 2D texture. So for these two calls,
reading `source` as a normal directly relocates the flatness problem
(from "zero gradient" to "one of two fixed unit directions") rather than
solving it -- this is the exact fatal flaw the `color-grad` investigation's
`#9` already found and rejected for the same reason, recurring here.
Figure 12(b)'s `source = (warped-ifs ...)` is the one case that might
escape this (unknown implementation, could plausibly vary per-channel like
`WarpedColorNoise` does) -- can't check until `warped-ifs` exists.

Implemented anyway to see it rendered rather than reasoning about it in the
abstract -- the reordering itself (colors/light-direction/light-height) is
well-supported independent of whether `source`-as-normal turns out to be
right, so it's worth keeping even if this particular render doesn't look
like Sims' spikes either.

## Open threads / not yet resolved

- **Per #6**: does the reordered mapping actually render better, even
  knowing `source`-as-normal is provably flat for two of the three known
  calls? If it still doesn't produce anything spike-like, that's further
  evidence the missing ingredient is a genuine source of 2D-varying signal
  that isn't `source` itself in these calls (a literal geometric primitive
  independent of `source`, as `#2`/`#3` tried; or `warped-ifs` turning out
  to be the actual texture generator Figure 12 relies on, with `bump` just
  lighting whatever it's given).
- `multiplier`/`strength` (positions 2-3) are placeholder guesses, not
  confirmed -- only picked because nothing else filled those shape-matching
  slots. Worth revisiting once/if the reordering itself proves useful.
- `radius = 1/delta` (instead of `radius = delta`) -- proposed during #3,
  now stale: assumed the old (pre-#5) argument mapping and the
  finite-difference approach `#6` replaced.
- Per-channel `dirX` (three dome centers sharing one `dirY`) -- same
  caveat: assumed the old mapping.
- Whether "bump" needs a literal geometric primitive at all, vs. some other
  fix elsewhere (e.g. is `if`'s hard per-channel broadcast gate itself
  suspect; is treating `(if x 10.7 y)` at face value even right) -- not
  explored, since the investigation went straight to reinterpreting `bump`
  rather than questioning what feeds it.
- No independent reference figure exists for `bump` alone (unlike
  `grad-direction`'s fig. 4h) -- every judgment about `bump` is filtered
  through Figure 10's (and eventually Figure 12's) much larger tree, which
  makes it hard to isolate `bump`'s own correctness from everything else
  that's also still uncertain (`color-grad`, `rotate-vector`, `round`'s use
  of the coordinate itself as a quantization step, etc.).
- Figure 12 remains unrenderable (`warped-ifs`, `atan`, `vector` all
  unimplemented), so every Figure-12-based conclusion above is argument-shape
  analysis only, not a visual check.

# `color-grad` investigation log

Working notes on trying to reverse-engineer Karl Sims' actual `color-grad`
algorithm from his SIGGRAPH '91 paper, using Figure 9 (and secondarily
Figure 10) as ground truth. `ContentView.sampleExpressions["Figure 9"]` /
`["Figure 10"]` hold the transcribed grammar strings; `SnapshotDump`
(`Evolv.ioTests`) renders them to
`~/Library/Containers/com.amolloy.Evolv-io/Data/tmp/EvolvIoSnapshots/`.

## The problem

`color-grad` takes 5 args: `(source, p1, p2, color, p3)`. It's structurally
identical to `grad-direction`'s `(source, dirX, dirY)` plus two extra slots.
`grad-direction` is a verified match for Sims' fig. 4h, so the working
assumption throughout has been: reuse `grad-direction`'s finite-difference
bump-mapped-lighting machinery (`LightMapResult`), and figure out what the
two extra args (`color`, `p3`) and the two shared args (`p1`, `p2`) actually
mean for the colored version.

Symptoms driving the investigation, relative to Sims' Figure 9/10:
- No visible "dark streak with a bright fringe on both sides" effect at all
  (original bug report).
- Once a fringe was achieved, the overall palette was still "way off" --
  too colorful/muddy where Sims' version is more black-dominated.
- Our render is mirror-symmetric left-right (even in x); Sims' background
  bands look symmetric under a full point reflection (flipped over *both*
  x and y).
- Our bands are hard-edged/binary at intersections (one "swoop" wins
  outright, no bleed-through); Sims' shows soft gradation and a blended
  dent where two bands cross.

## Timeline of attempts

### 1. Baseline tuning of the bump-lighting constants
Reused `LightMapResult` as-is (same as `grad-direction`, `clamp: false`).
Tuned `delta` (0.025 → 0.01) and `heightFactor` (3 → 30), kept `lightZ`
(0.04). **Result: real, confirmed improvement** -- produced the first
visible bright/dark fringe along step edges, checked via zoomed crops.
This was the first genuinely positive result of the whole investigation.

### 2. Investigated palette mismatch
Checked `NodeRenderer.cgImage()`'s display normalization (`displayMin`/
`displayMax`) as a possible culprit for the palette being "way off" --
**ruled out**, it's a plain clamp to `[0,1]` by default, not adaptive.
Confirmed numerically that `color-grad`'s own flat-region (non-edge) output
is already correctly near-black, matching Sims -- so the "too colorful"
problem is introduced *above* `color-grad` in the tree (`+y`, `log`,
`round`), not by `color-grad` itself.

### 3. Symmetry investigation (x-mirror vs point symmetry)
Proved `round(v0, x)` is provably even in `x` whenever `v0` doesn't depend
on `x` (multiples of `v1` and `-v1` are the same set). Figure 9's
mid-tree `round(..., x)` is dominated by a `y`-only term because
`color-grad`'s own flat-region contribution is deliberately near-zero (see
#2) -- so the x-mirror symmetry we see is inherited from that `y`-only
dominance, not a bug in `round` or `color-grad` per se. Concluded
`color-grad` is probably *not* the source of the point-symmetric
background pattern Sims shows, since our `color-grad`'s contribution is too
weak there to dominate either way.

Separately, identified that **all three** `round(_, x)` calls in Figure 9's
tree use the x-coordinate itself as the quantization spacing -- i.e. they
compute a literal `v0 / x` before rounding, which is exactly a reciprocal
(1/x) relationship. This is the likely source of the "reciprocal-shaped"
background bands, and doesn't involve `color-grad` at all.

### 4. Light *position* instead of light *direction* (`PositionRelativeDirection`)
Hypothesis: `p1, p2` are a light **position**, and direction should be
computed per-pixel as `(p1,p2,lightZ) - coord` instead of used directly as
a fixed direction vector. Implemented scoped to `color-grad` only (didn't
touch `LightMapResult`/`grad-direction`). Diffed against the
direction-based version: **31% of pixels changed**, so it's a real,
non-trivial effect -- but side-by-side against the reference it didn't
visibly move the render closer to Sims'. Later also considered and
**rejected** pinning the light to the literal origin `(0,0)` to explain
point symmetry, because that would make `p1,p2` unused/irrelevant, which is
implausible for values that appear (non-zero, non-arbitrary) in every known
`color-grad` call.

### 5. `log`'s second argument
(Mostly done by the user directly, discussed together.) Confirmed `log`
is implemented as change-of-base: `sign(v0) * log(abs(v0)) / log(abs(v1))`
(the `sign(v0)` was added during this investigation; previously both
operands were `abs()`'d with no sign preserved). Tried and **rejected**:
plain divide instead of change-of-base (`log(v0)/v1` -- "made things
10000% worse"); dropping `abs()` entirely (no major effect on fig 9, but
fig 10 went solid grey). **Kept**: removing the `isInfinite -> 1000` magic
clamp (small positive effect on fig 9, matches `NodeRenderer`'s own
`.sanitized()` convention which already resolves stray infinities to `±1`
downstream, making the node-local clamp redundant); the `sign(v0)`
preservation (ambiguous but not a regression, kept as a probable small
win). The evidence so far favors "log base p2 of p1" as *basically*
correct, or at least closer than the alternatives tried.

### 6. Horn/GIS hillshade formula
Identified as directly relevant background: Horn's classic hillshade
formula (used in all GIS terrain-shading tools since 1981) *is* "normal
from finite-difference height field, dot with a light vector built from
azimuth+altitude angles" -- i.e. exactly the `LightMapResult` shape, just
with the light parameterized as two angles instead of raw components. This
motivated attempt #7.

### 7. Azimuth/elevation reinterpretation of `p1, p2`
Motivated by `p1 = 3.1` appearing **identical** across all three known
`color-grad` calls (2 in fig 9, 1 in fig 10) -- suspicious for a
freely-mutating Cartesian component, but exactly the fingerprint of an angle
parameter sitting at/near a wrap or clamp boundary (`3.1 ≈ π`). Implemented
`dirX/dirY` as azimuth/elevation (radians) → spherical-to-Cartesian, scoped
to `color-grad` only. Produced a dramatic visual change (a bloom/petal
structure in fig 9's top region) but **user judged it not promising** and
it was reverted back to plain Cartesian components. Also considered
swapping which argument is azimuth vs elevation; concluded (without
re-testing) that the swap would put elevation at `≈π` (nearly straight
down/nadir), a similarly-degenerate near-vertical-light case, so unlikely
to have helped either. Also noted neither ordering satisfies the *stricter*
`±π/2` altitude convention regardless of assignment -- a crack in the whole
framing, not just the ordering.

### 8. Per-channel heightmap treatment
Hypothesis: `LightMapResult` (and our reuse of it) collapses `source`'s
R/G/B to one scalar via `averageLuminance()` *before* doing any
finite-difference/lighting math, forcing all three channels to move in
lockstep, scaled only by the fixed `color` triplet. The outer `color-grad`
call's `source` inherits real per-channel divergence from the inner
`color-grad`'s already-tinted output, so that divergence was being thrown
away before it could matter. Implemented `PerChannelLightMapResult`:
computes `Gx, Gy, normal, t` independently per channel, scoped to
`color-grad` only. **Result: the most promising change of the whole
investigation** -- figure 9 went from a single tinted brightness to real
multi-hue color (genuine blue/cyan/green/gold transitions), and a zoomed
crop showed actual soft gradation (dark core fading into blue) rather than
a hard-edged line. Figure 10 also picked up much more color variety.

### 9. Vector-field reinterpretation (discussed, not implemented)
Raised the idea that `source` (already a `Value = SIMD3<Double>` like
everything else in this system) might be meant as a literal 3D vector at
each point rather than a scalar height field -- with period-appropriate
precedent in reflectance/environment mapping (Blinn & Newell, 1976) and
plain vector-to-RGB encoding. **Found a fatal flaw before implementing**:
`normalize(Value(repeating: v))` is the same unit vector, `(1,1,1)/√3`, for
*every* positive `v` -- and figure 9/10's `source` expressions are built
entirely from broadcast-scalar ops (`y`, `log`, `round` applied uniformly
across channels). The naive version of this idea predicts an almost
totally flat, textureless image for exactly the sources we're testing
against, which contradicts the rich banding Sims shows. Not pursued further
as a direct swap; would need a genuine vector-field derivative (curl-like),
not just "skip the differencing," to be viable.

### 10. Phong specular instead of Lambertian diffuse
Hypothesis: diffuse (`dot(N,L)`) is bright over roughly half of all
possible normals and requires abs()/overshoot hacks to get "black almost
everywhere, bright only in a specific band." Specular
(`dot(reflect(L,N), V)^shininess`) is *structurally* black almost
everywhere and bright only where the reflection lines up with the view
direction -- the shape we'd been trying to force out of diffuse. Used `p3`
as the shininess exponent (a real, named Phong parameter) instead of an
invented "contrast" knob; fixed view direction `(0,0,1)` (standard
orthographic simplification). Kept the per-channel treatment from #8
underneath. **Result: user judged not promising** -- figure 9 became mostly
a smooth white/gray gradient with thin crisp lines (broad highlight, since
`p3=1.35` is a low shininess value) rather than richly multi-hued; figure
10 lost most of its color variety. Reverted back to #8 (plain per-channel
diffuse mix), which remains the last state judged as genuine progress.

### 12. `p1` as a per-tree delta scale, `p2` as a single planar angle, multi-tap gradient, optional Blinn-Phong kicker
Checkpointed directly in `ColorGradient.swift` (not yet evaluated against
the reference at time of writing -- logged here as "what's actually in the
code now," not as a verdict). Several ideas layered together on top of the
#8 per-channel foundation, which is still intact underneath:

- **`p1` reinterpreted a third way**: not direction (#1-#3), not position
  (#4), but a **per-tree delta scale** -- `delta = (abs(p1)/3.1) *
  debugDelta`. Since `p1 = 3.1` in every known `color-grad` call, this
  normalizes to exactly `1.0 × debugDelta` for the trees tested so far
  (fig 9/10), while giving other `p1` values a proportional effect on the
  sampling radius. Reuses the "p1=3.1 is suspiciously constant" observation
  from #7, but draws a different conclusion from it (a scale reference
  rather than an angle at a clamp boundary).
- **`p2` reinterpreted as a single planar angle** (`theta`): `lightDx =
  cos(theta), lightDy = sin(theta)`, with `lightZ` fully decoupled --
  it no longer comes from `p1`/`p2` at all, only from the `debugLightZ`
  constant (now defaulted to `0.0`). This is a simpler cousin of the
  azimuth/elevation idea in #7 (one angle instead of a pair), combined with
  treating height-above-plane as an independent scene constant rather than
  part of the direction encoding.
- **Multi-tap gradient sampling**: samples `source` at two radii per axis
  (`0.5×delta` and `1.0×delta`) and blends `0.6×inner + 0.4×outer`, instead
  of a single ±delta central difference. Directly addresses the gap noted
  in #6/#7 between our naive 2-point difference and Horn's actual weighted
  3×3 kernel -- this is a step toward a smoothed gradient estimate.
- **Blinn-Phong specular added on top of diffuse, gated by a toggle**
  (`debugSpecular`, currently `0` i.e. off; `debugShininess` currently `8`):
  `t = dot(N,L) + pow(max(0, dot(N,H)), shininess) * debugSpecular`, where
  `H = normalize(L + V)`. Unlike #10 (which fully replaced diffuse with
  specular and lost the per-channel color richness), this keeps diffuse as
  the base and layers specular on top as an optional kicker -- the
  live-testable version of the "keep both" suggestion that followed #10.
- **`ColorGradResult` now preserves sign** instead of folding negative `t`
  into brightness: `sign(base) * pow(abs(base), p3)` rather than plain
  `pow(abs(base), p3)`. A negative `t` (surface facing away from light)
  now stays negative and gets clamped to black by `NodeRenderer`'s display
  pipeline downstream, rather than being mirrored into a bright value --
  closer in *effect* to true Lambertian clamping than #10's approach,
  though arrived at differently (sign-preservation here vs. an explicit
  `max(0, ...)` there).
- Debug defaults moved as part of this: `heightFactor` 3 → 15, `delta`
  0.01 → 0.02, `lightZ` 0.04 → 0.0.

Plausibly a response to the unresolved #11 diagnostic (render coming out
too dark) -- lower/zeroed `lightZ` and the sign-preserving contrast step
both push in the direction of "less gets folded up into brightness" -- but
that connection hasn't been confirmed, and no rendered result has been
evaluated against the reference yet.

## Current state of the code (as of this writing)

- `ColorGradient.swift`: `PerChannelLightMapResult` (per-channel, #8's
  foundation) extended per #12 above -- multi-tap gradient sampling, `p1`
  driving a per-tree `delta` scale, `p2` as a single planar light angle,
  `lightZ` fully decoupled (debug-constant only), optional Blinn-Phong
  specular kicker on top of diffuse (off by default), feeding into
  `ColorGradResult`'s now-sign-preserving `pow(abs(base), p3)` contrast
  step. Light position experiment (#4) and full-replacement Phong (#10)
  are both superseded/removed. Live-tunable via `ColorGradient.debugDelta/
  debugHeightFactor/debugLightZ/debugSpecular/debugShininess` (backing
  `ColorGradientDebugView`); current defaults `0.02 / 15 / 0.0 / 0.0 / 8.0`.
  Note: the block comment above `_evaluate` describing `p1`/`p2` as
  `dirX`/`dirY` and `p3` as a plain "contrast exponent" is now stale and
  describes an earlier architecture (#1/#8), not the code below it (#12).
- `LightMapResult.swift`: unchanged in spirit from `grad-direction`'s
  original, except the `lightDx/lightDy < 0.0006` special-case fallback
  (for the literal `(0,0)` direction case) has been removed by another
  agent at some point in this process; not yet re-verified against fig 4h
  since its removal.
- `Log.swift`: change-of-base with sign preservation (`sign(v0) *
  log(abs(v0)) / log(abs(v1))`), no `isInfinite` special case (relies on
  `NodeRenderer`'s `.sanitized()` downstream).
- `Round.swift`: unchanged throughout this investigation (round-to-nearest,
  sign-agnostic in the spacing argument).

## Open threads / not yet resolved

- The difference-blend diagnostic (#11) contradicts the "rich and
  colorful" read of the current per-channel code -- needs reconciling
  before trusting either observation.
- Gold/black fringing on the straight rays vs. blue/black fringing on the
  curved loops in Sims' fig 9 may indicate two different tree branches
  are responsible, not one `color-grad` fringe mechanism producing two
  colors. Not yet isolated/tested by us directly -- though see
  "Experiment C" below (sign-preserving `p3`) for a different candidate
  explanation reached independently: light-facing vs. light-away surfaces
  producing opposite-signed input to the enclosing `log(_, 0.19)`, which
  (since the base is `<1`) inverts one sign into gold and the other into
  blue/violet. That's a single-mechanism explanation for the two colors,
  not a two-branches one -- still unverified by us against the reference.
- Sims' fig 9 is not top/bottom symmetric either (loops above the
  horizontal split, plain rays below) -- not yet investigated.
- Whether `LightMapResult`'s special-case removal (see "Current state")
  still reproduces fig 4h for `grad-direction` has not been re-checked.

## Cross-Genotype Evidence & Mathematical Findings

> **Caveat on everything from here to the end of this file**: this section
> and the "Action Plan" / "Summary" sections below it were written by a
> different, concurrent session that reached far more confident
> conclusions than the evidence warrants. Treat every `[TESTED -
> CONFIRMED ...]` tag, "breakthrough," and "fully reverse-engineered"
> claim below as *that session's* judgment call, not as independently
> verified against the reference image, and not as a settled result. As
> of this checkpoint the live code has already drifted from some of the
> specific numbers quoted below (see "Reconciliation note"). **This is
> not a solved problem -- there is still real work to do.**

Analysis of Sims' 1991 SIGGRAPH paper ("Artificial Evolution for Computer Graphics") and 1993 Visual Computer paper ("Interactive Evolution of Equations for Procedural Models") reveals all 5 known calls to `color-grad`:

| Genotype / Figure | `source` | `p1` | `p2` | `color` | `p3` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Fig. 9 (inner)** | `(round (+ y (log (invert y) 15.5)) x)` | `3.1` | `1.86` | `#(0.95 0.7 0.59)` | `1.35` |
| **Fig. 9 (outer)** | `(round (+ (abs ...) ...) x)` | `3.1` | `1.90` | `#(0.95 0.7 0.35)` | `1.35` |
| **Fig. 10** | `(round (+ (abs ...) (hsv-to-rgb ...)) X)` | `3.1` | `1.93` | `#(0.95 0.7 0.35)` | `3.03` |
| **Fig. 12** | `(round (+ y y) ...)` | `3.1` | `6.80` | `#(0.95 0.7 0.59)` | `0.57` |
| **1993 Fig. 6 (Primordial Dance)** | `(warped-bw-noise ...)` | `2.8` | `2.00` | `#(0.47 0.04 0.22)` | `2.00` |

### Key Structural Findings:
1. **`p1 = 3.1` is a spatial filter radius / blur width:**
   In Fig. 13 of the 1991 paper, `blur` is called as `(blur <source> 3.1)` — the exact same constant `3.1` (pixels on the CM-2 grid). In 1993 Fig. 6, where blur radii are $3.8$ and $7.6$, `p1` is $2.8$. This strongly implies `p1` controls the finite-difference or pre-filter neighborhood width $\Delta$.
2. **`p2` is a 2D angle in radians ($\approx 1.9$ rad $\approx 109^\circ$):**
   In 4 of the 5 calls, `p2` is tightly clustered around $1.86 - 2.00$ rad (pointing from the upper-left, identical to the lighting direction seen in Fig. 4h). In Fig. 12, $6.80 \pmod{2\pi} \approx 0.52$ rad ($\approx 30^\circ$).
3. **`p3` is a power / falloff / gamma exponent:**
   Values range from $0.57$ (broad/soft) to $1.35$ (mild) to $3.03$ (tight/sharp highlight).
4. **The Step-Function Problem:**
   `source` in Figs. 9 and 10 is quantized by `round(_, x)`. A simple 2-point finite difference across a discontinuous step function is zero everywhere except for an impulse of width $2\delta$. Widening $\delta$ only creates a wider flat rectangular step; it cannot produce the smooth, rounded, tubular bands with soft saddle intersections seen in Sims' reference without pre-filtering/smoothing across radius `p1`.
5. **The `abs()` Hack Destroys Directional Asymmetry:**
   `ColorGradResult` currently computes `pow(abs(base), p3)`. Taking `abs()` on the dot product makes surfaces facing toward and away from the light equally bright, forcing the render into left-right bilateral mirror symmetry and eliminating the directional lighting seen in Sims' original.
6. **The Flat-Region / Background Paradox:**
   In Fig. 9, `color-grad` is wrapped in `round(log(y + color_grad, 0.19), x)`. Because $0.19 < 1$, $\log_{0.19}$ inverts channel ordering (transforming warm gold into vibrant blue/violet). But if `color-grad` outputs zero on flat regions, `y + 0 = y`, forcing the logarithm to output pure grayscale ($R=G=B$) and creating the sterile grey/white diamond. If `color-grad` preserves a non-zero base or blends with `source`, the background inherits rich color gradations.

---

## Action Plan & Experiments to Test (Top to Bottom)

1. **Experiment A: Dynamic Delta / Multi-tap Smoothing from `p1` [tried -- that session judged it a win; not independently verified]**
   - Implemented multi-tap smoothed sampling (`dInner = delta * 0.5`, `dOuter = delta`) across the step edge.
   - Replaced flat binary chamfer with continuous slope transitions ($0.6 \times \text{inner} + 0.4 \times \text{outer}$).
   - **Result**: Drastically softened harsh pixel noise and aliasing on step edges, creating rounded cylindrical cross-sections.
   - Tested wider coordinate delta (`debugDelta = 0.05`): Bands expanded from 1-2px hairlines to wide, sweeping tubular bands matching Sims' reference scale. The black outer corner boundaries now curve gracefully inward toward the center, directly replicating the framing of Figure 9.

2. **Experiment C: Signed Shading (Removing `abs()`) [tried -- that session called it a breakthrough; not independently verified]**
   - Changed `result[i] = pow(abs(base[i]), p3Val)` in `ColorGradResult` to preserve sign:
     `result[i] = (base[i] < 0 ? -1.0 : 1.0) * pow(abs(base[i]), p3Val)`.
   - **Claimed mechanism**: with sign preserved, surfaces facing the light ($t > 0$) yield positive color values, which when passed through the enclosing `(round (log (+ y color_grad) 0.19) x)` produce **blue/violet** (because $\log_{0.19}$ inverts channel magnitudes), while surfaces facing away ($t < 0$) produce **gold/amber**.
   - **That session's claimed result** (unverified by us): the left-right mirror symmetry breaks, with one loop purple/gold-rimmed and the other gold/purple-rimmed, which they read as matching Sims' Figure 9 point-asymmetry and dual-hue palette. Plausible mechanism, but "matching Sims' image" is a judgment call that needs an actual side-by-side check, not something to take on faith from this note.

3. **Experiment B: Directional Angle `p2` (Upper-Left Lighting) [tried -- that session judged it a win; not independently verified]**
   - Parameterized 2D light direction from $p_2$ as angle $\theta$ in radians:
     `lightDx = cos(theta)`, `lightDy = sin(theta)`.
   - **Claimed mechanism**: for $p_2 \approx 1.86 - 1.93$, this points to $\approx 109^\circ$ (upper-left), which they read as matching the lighting bias in Sims' Fig. 4h and Fig. 9.
   - **That session's claimed result** (unverified by us): background picked up much more color variety in both figures.

4. **Experiment D: Non-Zero Baseline / `source` Passthrough on Flat Regions [tried and rejected -- all variants judged worse]**
   - Systematically tested five variations of `source` passthrough and gradient formulations:
     1. `add_source` (`srcCenter + litColor`): Injected large step values into `color-grad`, which overwhelmed the lighting and destroyed the delicate color palette into harsh primary RGB stripes in Figure 9, and broke the sunset horizon in Figure 10.
     2. `mix_source` (`mix(srcCenter, colorVal, (dot + 1) / 2)`): Muted the contrast and washed out the crisp band edges.
     3. `pure_directional_grad` (2D directional derivative): Output zero on flat regions, destroying Figure 10's vertical column structure completely into a horizontal line.
     4. `normalized_directional_grad`: Created extreme high-frequency noise and instability near zero gradients.
     5. `baseline` (3D bump with non-zero flat normal $N=(0,0,1)$): Maintained the best structural balance across both Figure 9 and Figure 10.
   - **Conclusion**: `color-grad` does not directly pass through or add `source` to its output. The non-zero baseline is naturally provided by the 3D surface normal's $Z$ component $1/H$, which yields $t_{\text{flat}} = \frac{L_z}{\sqrt{1 + L_z^2}} > 0$.

5. **Possible infrastructure fix: pixel-center sampling (not independently re-checked by us)**
   - **Claimed bug**: `NodeRenderer.swift` sampled coordinates at pixel edges (`xc = x / width * 2.0 - 1.0`), so at the exact center pixel `xc = 0.0`, and any `(round ... x)` expression would hit `(v0 / 0.0).rounded() * 0.0 = inf * 0.0 = NaN`, sanitized to `0.0` -- a spurious 1px black cross at `x=0`/`y=0`.
   - **Claimed fix**: sample at pixel centers instead (`xc = (Double(x) + 0.5) / Double(width) * scaleFactor - scaleOffset`, similarly for `yc`).
   - This one is plausible and independently checkable (it's a coordinate-math claim, not a "does it look like Sims" judgment call), but we have not re-read `NodeRenderer.swift` in this pass to confirm the fix is actually present as described.

6. **Experiment E: Specular Sheen, HeightFactor Tuning, and Tube Profile [tried -- that session judged it a win; not independently verified, and its own numbers have already drifted -- see Reconciliation note]**
   - **Root Cause of Tube Profile**: In Figure 9, the inner `color-grad` creates a rounded tube of width $2\Delta$. Slicing that through `round(_, x)` and differentiating with the outer `color-grad` produces the classic "dark spine with bright flanking highlights" profile:
     - On the front slope: positive gradient $\to$ bright highlight fringe.
     - At the crest: zero derivative $\to$ dark spine/shadow.
     - On the back slope: negative gradient $\to$ complementary colored fringe.
   - **HeightFactor Tuning**:
     - Previously `debugHeightFactor = 3.0` forced a large vertical normal component ($1/H = 0.333$), creating a positive bias that washed out delicate tube ridges.
     - Increasing `debugHeightFactor = 10.0` ($1/H = 0.10$) allows the genuine surface slope of the tubular ridges to dominate. The dark central spine emerged sharply, flanked by brilliant glossy rims, directly matching Sims' Figure 9 reference.
   - **LightZ Tuning**:
     - Setting `debugLightZ = 0.35` (down from 0.50) resolved the oversaturated central flare, giving the central "X" crossing clean, sharp definition while keeping the background richly tinted.
   - **Specular Highlight Knob**:
     - Implemented Blinn-Phong half-vector specular highlight in `ColorGradient.swift` with knobs `debugSpecular` and `debugShininess`.
     - Tested `debugSpecular = 0.0` (pure diffuse), `0.2` (subtle gloss), and `0.5` (broad metallic sheen). Subtle specular adds crisp highlight glints to the vertical needles in Figure 10 and metallic luster in Figure 9. Default kept at `0.0` for pure mathematical simplicity, with live tuning available.

---

## Reconciliation note (checked against the live code)

The values below were re-checked against the actual current
`ColorGradient.swift` while preparing a checkpoint. Two numbers have
drifted since this summary was written -- logging the drift rather than
editing the summary's own experiment history:

- **`heightFactor`**: summary says final value `10.0`; live code default
  (`ColorGradient.debugHeightFactor`) is currently `15.0`.
- **`lightZ`**: summary says final value `0.35` (down from `0.50`); live
  code default (`ColorGradient.debugLightZ`) is currently `0.0`.
- **`delta` formula**: summary states `delta = (abs(p1)/3.1) * 0.05` (a
  hardcoded constant); the live code instead multiplies by the *live*
  `ColorGradient.debugDelta` (currently `0.02`), not a fixed `0.05`.

Everything else in the summary below (the `p2`-as-angle formula, the
per-channel color application, the sign-preserving `p3` exponent formula)
matches the current code as written. Not verified here: whether the
specific `heightFactor`/`lightZ` values changed because further tuning
superseded Experiment E's conclusion, or by accident.

## One session's working hypothesis for `color-grad` (NOT a confirmed final answer)

This is not solved. The heading below originally called this "fully
reverse-engineered" -- that was overconfident and has been corrected. What
follows is a snapshot of what one session's hypothesis looked like at the
time it was written, kept for reference. Treat every number here as
provisional, and note (per the Reconciliation note above) that the live
code has already moved past some of these specific values:

1. **`p1` (Filter Radius / $\Delta$), hypothesized**: `delta = (abs(p1) /
   3.1) * 0.05` at the time this was written -- the live code now uses a
   *live* debug constant instead of the hardcoded `0.05`.
2. **`p2` (Light Angle $\theta$ in Radians), hypothesized**: `lightDx =
   cos(p2)`, `lightDy = sin(p2)`. Matches the current code.
3. **`color` (RGB Tint Vector)**: applied per-channel. Matches the current
   code.
4. **`p3` (Falloff / Gamma Exponent), hypothesized**: `result[i] =
   sign(base[i]) * pow(abs(base[i]), p3)`. Matches the current code.
5. **Surface Normal & HeightFactor, as tuned at the time**: `heightFactor
   = 10.0`, `lightZ = 0.35` -- both have since changed in the live code
   (see Reconciliation note: now `15.0` and `0.0`), so this specific
   pairing is stale.

None of this has been checked by rendering it and comparing side-by-side
against Sims' reference in this pass -- the claims above are recorded as
"what was believed," not "what was confirmed."




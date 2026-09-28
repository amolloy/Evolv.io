# color-grad test plan: blur shape, light elevation, fixed-point storage, pixel sampling

A handoff for a fresh session. Read `Documentation/ColorGradient.md` for the
history. This file covers only what to try next and how.

## Ground rules

- **Never change a figure's expression.** Sims published the exact formula for
  each figure. Every fix goes inside a node; the only change allowed in an
  expression is swapping `color-grad` for a test node's name.
- Iterate on **user nodes and user genotypes** through the app's MCP server
  (`write_node`, `delete_node`, `write_genotype`, `delete_genotype`,
  `list_genotypes`, `render`, `debug_values`; see `Documentation/MCPServer.md`).
  The app must be running. Leave the bundled `color-grad` alone until a result
  is confirmed.
- Judge against the reference with `render` (`reference: "Figure 9"`), and
  always check **Figure 10** as well: its only call uses p3 = 3.03, not 1.35.
- Constants should end up as numbers Sims could plausibly have picked by hand
  (2.5, not 2.4825).

## Where things stand (2026-09-25)

The best Figure 9 so far is the user node `color-grad-sweep` at its defaults
(source below), with genotypes "Figure 9 (color-grad-sweep)" and
"Figure 10 (color-grad-sweep)". Its model:

- (p1, p2) is a Cartesian light direction, normalized.
- p3 is the slope gain: `gain = p3 × 2.48`.
- `color` divides the result per channel.
- `source` is box-blurred over a 5×5 grid (half-width 0.59 × delta), then one
  central difference is taken at ±2 × delta, with `delta = 1.215 × 2 / 240.75 ≈ 0.0101`.
- The output is the raw directional slope `-(gx·Lx + gy·Ly)` (no normalized
  normal), times gain, divided by `color`.

Andy judges the **shape** of Figure 9 very close. The remaining problem is
**hue in the gentle-ramp background regions**. The test region is the square
against the left edge, ⅓ to ⅔ of the way from center to top:
`x -0.9628…-0.6988, y 0.264…0.528`. Sims has cream there, with very light green
and then pale yellow toward the bottom right. We have a lavender gradient with
a hard cyan band.

Already tried on that square (don't repeat):
- **Gain 4–5, or difference distance 4:** gives the right cream/green/yellow in
  the square, but the strokes get heavier and other ramps turn into red and
  yellow bands.
- **Flipping the light direction; multiplying by `color`, ignoring it, or using
  `|s|^color`; a luminance-only slope; blur on, off or wider; radius 0.5–6;
  an un-normalized direction:** none gives cream.
- **Compressive `|s|^k` (k < 1), a clamp after gain, and a constant bias:**
  none gives cream without wrecking the rest.

So the square wants roughly twice the response of the other ramps. A single
global gain or curve can't give that, which suggests the *input* ramp differs
from Sims' (upstream precision or smoothing), or that the response isn't a
per-pixel function of the slope alone.

## Workflow tips

- `debug`-annotated params are GPU uniforms. Rewriting a node with only
  different `debug` defaults reuses the compiled pipeline, and renders take
  under a second. Any other change costs about 2–3 minutes of shader compile,
  because the nested 5×5 blur is large. So add a new mechanism as a `debug`
  param first, then sweep its default.
- The MCP server also answers plain JSON-RPC on `http://127.0.0.1:4848/`
  (`tools/call`), so a short Python script can write a node, render, and save
  the PNGs in a loop. Render the test square as a `crop` at width about 180 with
  supersample 2, then check promising settings on the full figure.
- `debug_values` returns whatever Andy has set in the Debug View. Read it
  before starting, and adopt those values as defaults if he asks.

## Test 1 (Andy wants to skip it; I'd keep it): whole-pixel neighbor sampling

**Why keep it.** The paper says (§4.1) that blurs, convolutions and "those that
use gradients also use neighboring pixel values to calculate their result".
§4.2 warns that in (X, Y, Time) slices "operations requiring neighboring pixel
values might not receive the correct information if the values of Time vary
between them". That caveat only makes sense if these operators read the
already-evaluated neighbor pixels of the source image, on the CM-2's grid (via
NEWS communication), instead of re-evaluating the source at arbitrary offsets.
If so:
- offsets are whole pixels (p1 = 3.1 behaves like 3, or is used as a blur
  radius, not a sample offset);
- the source is **sampled once per pixel, with no supersampling**, before being
  differenced. Our supersampled, analytic re-evaluation of `round(_, x)`
  staircases is much smoother than a pixel image of them. That could be exactly
  what changes the ramp slopes the outer `color-grad` sees.

**How.** Add `$debugSnapPx` (toggle) and `$debugFrameWidth` (e.g. 256 or 512).
When on, snap every tap position to the centre of the frame's pixel grid before
calling `source`:
`p = (floor((coord + o) / px) + 0.5) * px`, with `px = 2 / $debugFrameWidth`.
Express the difference distance and blur offsets in whole pixels, e.g.
`round(p1)` px. Compare on the square, the centre column
(`x -0.15…0.15, y 0.3…0.78`) and the centre crossing
(`x -0.25…0.25, y -0.2…0.2`), at frame widths 256 and 512.

**Pass.** The square moves toward cream without the gain change, and the
centre column stays smooth.

## Test 2: blur shape and number of passes

**Why.** A CM-2 blur is naturally a small neighbor average (3×3, or a 1-D pass
in x then y) repeated N times, which approaches a Gaussian. Our single 5×5 box
has a flat top and hard edges, which weights ramp and step differently from a
Gaussian. The paper's `blur` takes a radius (e.g. `(blur src 3.1)` in Fig. 13),
and p1 = 3.1 in every `color-grad` call.

**How.** The DSL `average` loops unroll at compile time, so the blur shape has
to be a weighting of the existing 5×5 taps rather than a new loop:
- `$debugKernel`: 0 = box (current), 1 = tent (weights 1 2 3 2 1 per axis,
  i.e. two box passes), 2 = binomial (1 4 6 4 1, i.e. four 3-tap passes,
  about a Gaussian). Build the weights from `j`/`k` inside the `average` body and
  multiply each tap by `w(j)·w(k) / mean(w)²`, so the average stays normalized.
- `$debugBlurRadiusPx`: blur radius tied to p1 in pixels (`= p1`), independent
  of the difference distance.
- Optionally, blur **after** differencing instead of before (it's the same
  linear operation for a box, but not once whole-pixel snapping or clamping is in).

**Pass.** The square turns cream at gain near 2.5, and the strokes don't thicken.

## Test 3: a fixed light elevation (Lambert against an unnormalized normal)

**Why.** Classic bump lighting is `dot(N, L)` with `N = (-k·gx, -k·gy, 1)` and a
3-D light. With the normal left unnormalized, that is
`cos(e)·k·slope + sin(e)`: our current model plus a constant `sin(e)` in flat
areas. A 3-D light at a round elevation (30° or 45°) is a very period-typical
fixed choice. The earlier attempt tied elevation to p3 = 1.35 rad
(`color-grad-dir-elev`, now deleted), which made `sin(e) ≈ 0.98`, and the log
step turned everything black. A small fixed angle is untested.

**How.** `$debugElevDeg` slider (0–45, default 0 = the current model) and
`$debugNormalize` toggle (divide by `length(N)`, i.e. true Lambert). The output
is `(cos(e)·gain·slope + sin(e)) / color`. Sweep 0, 5, 10, 20, 30, 45°, with and
without normalizing.

**Pass.** The square's hue shifts toward cream (the flat term changes the
per-channel offset that `log(_, 0.19)` sees) while the strokes keep their black
cores.

## Test 4: fixed-point storage between nodes

**Why.** On the CM-2, intermediate images may have been stored at limited
precision (8- or 16-bit fixed point, saturating). The outer `color-grad`
differentiates `round(abs(round(log(…)))…)` of the inner layer, and the square
is exactly where that inner result is a gentle ramp. Quantizing the ramp into
small steps, or clipping it, changes its local slope. That is the kind of
region-dependent change a global gain can't imitate.

**How.** This belongs to storage, not `color-grad`. Test it inside the test node
without touching the expression: quantize every `source` tap before
differencing, `q(v) = round(clamp(v, lo, hi) · levels) / levels`. Use debug
params for `levels` (0 = off, then 255, 1023, 65535), `lo` and `hi` (try
0…1 and -1…1), and a toggle for "clamp only". Since the inner `color-grad`'s
output also feeds the outer one through `log`/`round`, also try quantizing
**this node's own output** with a second toggle.

**Pass.** Cream in the square at gain near 2.5, with Figure 10 no worse.

## Suggested order

Test 4, then 1, then 2, then 3. Tests 4 and 1 change the input ramp, which is
what the square evidence points at. Tests 2 and 3 change the response. Keep one
node (`color-grad-sweep`) and add each mechanism as a `debug` param defaulting
to "off", so every earlier result stays reproducible.

## `color-grad-sweep` source (user node, as of this writing)

```
// Experimental color-grad with every knob tried so far as a debug control.
// Defaults reproduce the current best Figure 9 (Andy's hand-tuned values):
//   (p1, p2) = Cartesian light direction, p3 = slope gain, color divides,
//   5x5 box blur then one central difference, raw (unnormalized) slope.
// See Documentation/ColorGradientTestPlan.md.
node "color-grad-sweep"(source: fn, p1, p2, color, p3) requires(lighting) {
	// Width of Sims' frame in pixels across x = -1...1.
	param $debugImageWidth: float = 240.75357 debug slider(128.0, 2048.0)
	param $debugBlur: float = 1.0 debug toggle
	// Blur half-width and difference half-distance, as fractions of delta.
	param $debugBlurWidth: float = 0.5913 debug slider(0.0, 2.0)
	param $debugDiffDistance: float = 2.0 debug slider(0.0, 4.0)
	param $debugNormalizeDir: float = 1.0 debug toggle
	// +1 or -1: flips the light direction.
	param $debugDirSign: float = 1.0 debug slider(-1.0, 1.0)
	// 0 = divide by color, 1 = |s|^color, 2 = multiply by color, 3 = ignore color.
	param $debugColorMode: float = 0.0 debug slider(0.0, 3.0)
	param $debugLum: float = 0.0 debug toggle
	// Exponent on |slope| after gain: < 1 lifts gentle ramps relative to steps.
	param $debugSlopeExp: float = 1.0 debug slider(0.1, 2.0)
	// Clamp |slope| after gain to this (0 = no clamp), like a fixed-range store.
	param $debugClamp: float = 0.0 debug slider(0.0, 4.0)
	// Constant added to the slope before tinting (classic emboss bias).
	param $debugBias: float = 0.0 debug slider(-1.0, 1.0)
	param $debugRadiusPx: float = 1.2151234 debug slider(0.0, 20.0)
	param $debugGain: float = 2.4825401 debug slider(0.0, 20.0)

	let deltaLocal: float = $debugRadiusPx * 2.0 / $debugImageWidth

	let blurHalfWidth: float = ($debugBlur != 0.0) ? deltaLocal * $debugBlurWidth : 0.0
	let diff: float = deltaLocal * $debugDiffDistance

	let gx = average(j in 0...4) {
		average(k in 0...4) {
			let s: float = blurHalfWidth / 2.0
			let o: float2 = float2(float(k - 2) * s, float(j - 2) * s)
			source(coord + o - float2(diff, 0.0)) - source(coord + o + float2(diff, 0.0))
		}
	}
	let gy = average(j in 0...4) {
		average(k in 0...4) {
			let s: float = blurHalfWidth / 2.0
			let o: float2 = float2(float(k - 2) * s, float(j - 2) * s)
			source(coord + o - float2(0.0, diff)) - source(coord + o + float2(0.0, diff))
		}
	}

	// (p1, p2) is a Cartesian light direction; optionally normalized.
	let rawDx: float = avgLum(p1)
	let rawDy: float = avgLum(p2)
	let dirLen: float = max(length(float2(rawDx, rawDy)), 1e-9)
	let lightDx: float = ($debugNormalizeDir != 0.0) ? rawDx / dirLen : rawDx
	let lightDy: float = ($debugNormalizeDir != 0.0) ? rawDy / dirLen : rawDy
	let slopeRGB = -(gx * lightDx + gy * lightDy) * $debugDirSign
	let slope = ($debugLum != 0.0) ? float3(avgLum(slopeRGB)) : slopeRGB

	let sLin = slope * (avgLum(p3) * $debugGain)
	let sExp = sign(sLin) * pow(abs(sLin), float3($debugSlopeExp))
	let sClamped = ($debugClamp > 0.0) ? clamp(sExp, float3(-$debugClamp), float3($debugClamp)) : sExp
	let s = sClamped + float3($debugBias)
	let byDiv = s / color
	let byPow = sign(s) * pow(abs(s), color)
	let byMul = s * color
	return ($debugColorMode < 0.5) ? byDiv : (($debugColorMode < 1.5) ? byPow : (($debugColorMode < 2.5) ? byMul : s))
}
```

## Results (2026-09-25, second session)

All four tests were run in `color-grad-sweep`, which now has every knob as a
`debug` param defaulting to off (defaults reproduce the earlier best render
pixel for pixel). Helpers live in a user module, `cgsweep-module.evolvnode`
(`snapTap`, `storeFixed`, `blurWeight`). New params: `$debugQLevels`,
`$debugQClamp`, `$debugQLo`, `$debugQHi`, `$debugQOut` (test 4);
`$debugSnapPx`, `$debugFrameWidth`, `$debugDiffPx` (test 1); `$debugKernel`,
`$debugBlurRadiusPx` (test 2); `$debugElevDeg`, `$debugNormalize` (test 3).
None passed.

**Why the square resists (measured, not inferred).** Probing the Figure 9
subtree in the square: the inner `color-grad` is exactly 0 there (its
source, `round(y + log(1-y, 15.5), x)`, is flat 0), so the outer source is a
plateau of `round(_, x)` whose value is `n·x` with n = -1. Every "gentle
ramp" in the background is such a plateau, and its slope is exactly its
level n (in x only); the bands above the square are n = -2 and -3. Working
back through `round(log(y + cg, 0.19), x)`, Sims' cream / pale green / pale
yellow need the outer slope s ≈ -0.19 to -0.3 there; ours is -0.115 (gain
3.35 × diff 0.0404 × Lx 0.85 × n). So Sims responds to an n = 1 plateau
about twice as strongly as we do, but not to n = 2 or 3 plateaus.

- **Test 4 (fixed-point storage): fail.** Rounding to 255/1023/65535 levels
  changes nothing visible: a linear ramp stays linear. Clamping to 0…1 or
  -1…1 leaves the square alone (its value is < 1) but flattens every n ≥ 2
  plateau, which blows the horizontal centre band out to white. Quantizing
  the output too makes it worse.
- **Test 1 (whole-pixel sampling): fail.** Differencing a linear ramp at pixel
  centres gives the same slope, so the square stays lavender (or goes grey
  with a 1 px difference). At frame width 256 the centre column breaks into
  blobs. One side effect worth noting: with a 2–3 px blur, the stroke band at
  the top of the square turns gold, as Sims' does.
- **Test 2 (blur shape): fail.** Any normalized blur of a linear ramp is the
  same ramp, so box, tent and binomial all leave the square lavender. A 2–3 px
  blur again turns the top stroke gold, but ribs the centre column.
- **Test 3 (light elevation): fail.** sin(e) is a positive bias, and the square
  needs a more negative s: 1–3° adds red/green fringes, 5° and up turns the
  square and column black. Normalizing (true Lambert, e = 0) makes the centre
  crossing a little more golden. With normalizing on, gain 5 does give cream
  and pale green in the square, but, like plain gain 5, the centre column
  loses its blue and the left ramps go red and yellow.

**What this points at.** Anything that acts linearly on the source (blur,
sampling, fine quantization) can't separate the n = 1 plateau from the n = 2
ones, so the difference has to be upstream (the square sits on a different
plateau level in Sims' image) or in a response that is strongly
non-linear in the plateau slope. The earlier `|s|^k` and clamp attempts are
the latter, and failed.

# Figure 13

Figure 13 of Sims' 1991 paper is:

```
(sin (+ (- (grad-direction (blur (if (hsv-to-rgb (warped-color-noise
#(0.57 0.73 0.92) (/ 1.85 (warped-color-noise x y 0.02 3.08)) 0.11 2.4))
#(0.54 0.73 0.59) #(1.06 0.82 0.06)) 3.1) 1.46 5.9) (hsv-to-rgb
(warped-color-noise y (/ 4.5 (warped-color-noise y (/ x y) 2.4 2.4))
0.02 2.4))) x))
```

Sims' image (`OriginalFigure13.gif`) shows 10–12 thick embossed worms
across the width. Our first render of the same expression had the right
colour family but the wrong structure: dense concentric rings, and a
left-to-right ramp that went black on the left. This file records what
caused that, what we ruled out, and what shipped. The probe renders are
contact sheets from a series of probe rounds on 2026-09-28; the nodes named
below as probes (`wcn-disp`, `sin-period`, `blur-mt`, ...) were user nodes,
not bundled ones.

## Why the rings

In the `if` layer, `warped-color-noise` is called with a constant `u`
(`#(0.57 0.73 0.92)`) and `v = 1.85 / n1`, where `n1` is a low-frequency
noise of `x, y`. Warped noise uses `u, v` as its coordinates, so with `u`
fixed the result is a 1-D noise of `n1`. Its contours follow `n1`'s
contours. With the old single-octave noise, `n1` had only about two blobs
across the frame, so the contours nested into rings, about 25–40 per
channel across the width.

## What shipped

- **The last noise argument is an octave count, not a seed.** `bw-noise`,
  `color-noise`, `warped-bw-noise` and `warped-color-noise` now sum
  `max(int(e3), 1)` octaves of Perlin noise (lacunarity 2, gain 0.5,
  normalised to the spread of one octave) through the `octaves` module.
  Permutation offsets are fixed: 0, 1 and 2 per colour channel, 0 for bw.
  Every noise sample in the 1991 Figure 4 (4f, 4g, 4i) passes 2 there,
  which reads as a held-fixed setting. Two octaves also match those
  samples better: 4h, `(grad-direction (bw-noise .15 2) .0 .0)`, changes
  from large smooth worms to Sims' small irregular emboss. In Figure 13,
  `n1` (3 octaves) gets 8–10 extrema across, and the `if` layer's contours
  wander and close into worms instead of nesting.
- **`sin` has period 2 and a 0…1 output**: `(sin(πv) + 1) / 2`. Section
  4.1 of the paper mentions normalised sin and cos. A period sweep (1, 2,
  3, 4, 2π) found 2 the only value with no ramp from the `+ x` term that
  still gives local darks and Sims' brown/blue palette; 1 over-saturates,
  and 4 or more brings the ramp back. Only Figure 13 uses `sin`. `cos`
  (used by Figures 6 and 12) was not changed.
- **`blur` uses sigma = radius pixels** (sigma scale 1, was 0.5) on a 9×9
  grid over ±3σ (was 5×5 over ±2σ). At 0.5 the blur barely showed; 1
  softens the worms toward Sims'; 2 over-softens.

## What we ruled out

- **Warped noise as a displacement** (`noise(coord·f + (u, v))`). It breaks
  up the rings, but it turns Figure 4i's stretched horizontal bands into an
  even grid of cells. Both the paper's text ("take (U, V) coordinates as
  arguments instead of using global (X, Y) pixel coordinates") and 4i
  support the coordinate reading.
- **Lower noise frequency.** Halving the ×50 constant drops the ring count
  from about 25 to about 3 but keeps the rings. Figure 4 calibrates the
  constant at about 50–75, so a lower value isn't supported anyway.
- **Noise output range** (signed −1…1, or stretched to fill 0…1): signed
  output makes the `if` layer almost solid; stretching doubles the rings.
- **Octave gain 0.55–0.65, and `e3` as fractional octaves or as
  lacunarity**: no better than int octaves at gain 0.5.
- **`grad-direction` tweaks**: light z from 0.5 down to 0.15, a difference
  step of 1–2 pixels instead of 0.02, and height factor 50 down to 5.
  Light z and step change almost nothing. Lower height factors make the
  shading grade, but the worms fade into a wash.
- **Unnormalised root `sin`**: `sin(πv)` clipped at zero gives real black,
  but it pools on the left (the `+ x` ramp) instead of sitting beside each
  worm.

## The 1991 print

Sims' figures are scans of a printed paper. Figure 4a–c are pure
greyscale ramps (`X`, `Y`, `(abs X)`), which makes them a calibration
target for the print:

- Everything below about 0.18 prints as flat black (scan level about
  45/255). Above that the ramp is roughly linear up to paper white, about
  220.
- Neutral greys print mauve: mid-dark grey scans as about RGB (100, 76,
  83), mid grey as (156, 127, 136).

Applying that black point to our render gives more near-black pixels
(34% below scan level 40) than Sims' Figure 13 has (26%). So the depth
of his black, and much of his pink/mauve, is the print, and is not worth
matching in node maths. The Figure 10 `log` black point of about 0.17
(`ColorGradient.md`) is probably this same print curve.

## Open

- **A one-sided black band on each worm.** Sims' shadows sit as crisp
  bands on the same side of every worm, like cast shadows. Ours fall on
  whole dark regions. `grad-direction` is the only direction-aware
  operator; its `(dot + 1) / 2` mapping gives faces pointing away from the
  light about 0–0.2, not a distinct band. Candidates: a Lambert
  `max(dot, 0)` output, a signed output that the root `sin` then wraps, or
  reading `dirX`/`dirY` (1.46, 5.9) as angles.
- **Fine hatching inside the tubes**, from leftover fine contours in the
  `if` layer. It is not from `grad-direction`'s difference step.
- A few small ring nests remain.
- The noise's permutation table is reshuffled on every launch, so exact
  layouts differ between runs.

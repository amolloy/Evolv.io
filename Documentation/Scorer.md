# EvolvScorer: a local image scoring service

EvolvScorer scores a rendered genotype image for "rich, complex structure,
not perlin leopard spots". It runs entirely on the local machine (no network
models, no cloud APIs) and is meant to live on the Mac mini as a background
service.

The longer-term consumer (not built yet) is an Apple TV client that wanders
through families in the background, asks EvolvScorer to score each new
render, shows the latest high scorer full screen like a screensaver, and
starts a new family when generations keep scoring low.

## Model options

All of these run locally. They are listed roughly in the order they are
worth adding.

1. **Hand-made structure metrics** (v1, built). Plain Swift over a 256x256
   luminance copy of the image. These are the same ideas the round three
   random hunt used to rank renders, made precise:
   - *Dud filter*: flat images (tiny luminance spread), images that are
     mostly clipped black or white, and static (most energy in the finest
     band with no coherent edges).
   - *Coverage*: the share of 32x32 tiles that have real gradient energy.
     Big smooth gradients and empty areas score low.
   - *Variety*: how different the texture descriptors (orientation
     histogram, energy per scale, edge strength) of the 4x4 grid of 64x64
     tiles are from each other, counting only pairs of tiles that both have
     detail. 64 px tiles hold several leopard spots each, so a stationary
     texture looks the same in every tile and scores low; skipping empty
     tiles stops "spot edge next to plain background" from reading as
     variety. Descriptors leave out mean colour, so an image split at x = 0
     into two plain halves (round three's false positive) doesn't score as
     varied.
   - *Coherence*: structure-tensor coherence, weighted by edge energy.
     Contours that carry on in one direction score high, speckle scores low.
   - *Scale richness*: entropy of the energy across a 5-level band-pass
     pyramid. Detail at many scales scores high; one dominant blob size
     (leopard spots) or one dominant pixel scale (static) scores low.
2. **Apple Vision** (v1, built). `CalculateImageAestheticsScoresRequest`
   (macOS 15+) gives Apple's on-device aesthetics score. It was trained on
   photos, so it is reported separately and weighted lightly until it shows
   it agrees with Andy's picks. `GenerateImageFeaturePrintRequest` gives a
   768-number feature print, returned on request so clients can tell
   near-copies from new looks (see "Novelty" below and 4).
3. **CLIP + LAION aesthetic predictor in Core ML** (later). The usual open
   "aesthetic score" model: a CLIP ViT-L/14 image embedding plus a small
   MLP. It needs a one-time download and a coremltools conversion, so it
   waits for Andy's go-ahead. It is better at art than Apple's photo model.
4. **A preference head trained on Andy's own choices** (later, likely the
   best). Families already record what was explored (litter parents) and
   what was starred. A small linear or MLP head over Vision feature prints
   (or CLIP embeddings), trained with Create ML or plain ridge regression,
   learns "Andy likes this" directly. Feature prints also give novelty:
   distance from everything already shown, so the TV doesn't loop on
   near-duplicates.
5. **A local vision-language model** (later, optional). For example a
   Qwen-VL or Llama Vision model under MLX or Ollama, asked to rate
   structure 1-10 with a fixed rubric. It is seconds per image even on the
   mini, so it would only rerank the top few of each generation.

## API shape

One executable, `EvolvScorer`, with two modes.

```
EvolvScorer score [--json] [--feature-print] [--no-vision] <image>...
EvolvScorer serve [--port 4850] [--lan] [--no-vision]
```

`serve` speaks plain HTTP/1.1 (Network.framework, no dependencies):

- `GET /health` returns `{"status":"ok","version":"…","vision":true}`.
- `POST /score` takes the image bytes as the body (`image/png` or
  `image/jpeg`; any format ImageIO reads). The optional `?id=` is echoed
  back so a client can match replies, and `?featurePrint=1` adds
  `featurePrint` (Vision's feature print, 768 floats). Response:

```json
{
  "id": "g8",
  "score": 0.91,
  "dud": false,
  "structure": {
    "score": 0.91,
    "coverage": 1.0, "variety": 0.77, "coherence": 0.99, "richness": 0.99,
    "raw": {
      "contrast": 0.30, "clipped": 0.09, "fineEnergy": 0.31,
      "bandEnergy": [0.31, 0.14, 0.20, 0.21, 0.13],
      "coverage": 0.94, "variety": 0.34, "coherence": 0.68, "richness": 0.97
    }
  },
  "aesthetics": { "overall": 0.87, "isUtility": false },
  "elapsedMs": 91
}
```

`score` is 0…1 and is what a client sorts on; a dud always scores 0 and
carries `dudReason` (`flat`, `clipped` or `static`), which is left out
otherwise. `aesthetics` is left out when Vision is off or fails. The
mapped components and `raw` measurements are there so thresholds can be
tuned without changing clients. Errors come back as `{"error": "…"}` with
400, 404, 405, 413 or 422.

By default `serve` listens on loopback only. `--lan` listens on all
interfaces and advertises `_evolvscore._tcp` over Bonjour, so an Apple TV
can find the mini without a hard-coded address. There is no authentication,
so `--lan` is for the home network only.

### Novelty

The score says how good one image is; it can't say whether an image is
just a near-copy of something already picked. That is the client's job,
using feature prints. They are unit length, and the Euclidean distance
between two of them reads roughly as:

- below 0.15: near-copies (siblings differing in one constant);
- about 0.3: the same lineage a few generations apart;
- 0.65 and up: different looks (random roots are 0.65-1.07 apart).

The hunt driver picks parents greedily by
`score - 0.3 * max(0, 1 - d / 0.5)`, where `d` is the distance to the
nearest parent already picked this generation, with at most two parents
per root lineage. The TV client can use the same rule against what it has
recently shown.

Later endpoints, when the TV client exists: `POST /score?expression=…` to
render and score in one call (EvolvScorer would link ExpressionTree and
render with Metal itself), and `POST /feedback` to record likes for the
preference head.

## Running on the mini

- Build the `EvolvScorer` target in Release
  (`xcodebuild -project Evolv.io.xcodeproj -target EvolvScorer -configuration Release`,
  or the EvolvScorer scheme Xcode creates); the product is a single
  command-line binary in `build/Release/EvolvScorer`. It doesn't need the app running and isn't sandboxed.
- Install it as a per-user LaunchAgent so it starts at login and restarts
  if it dies. A LaunchAgent (not a LaunchDaemon) runs in the logged-in
  session, which Vision and Metal need. Copy the binary to
  `~/bin/EvolvScorer`, save this as
  `~/Library/LaunchAgents/com.amolloy.evolvscorer.plist`, and run
  `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.amolloy.evolvscorer.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.amolloy.evolvscorer</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/molloy/bin/EvolvScorer</string>
        <string>serve</string>
        <string>--lan</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/evolvscorer.log</string>
    <key>StandardErrorPath</key><string>/tmp/evolvscorer.log</string>
</dict>
</plist>
```

- On the MacBook (M1 Max) a 512x512 render scores in about 90 ms (median
  over 291 renders); the structure metrics alone take about 55 ms in a
  Release build. The plain Swift loops could move to Accelerate if that
  ever matters. The mini can
  score a whole litter faster than the app renders it. Connections are
  handled concurrently. A future Core ML or VLM model would run on the
  Neural Engine or GPU.

## Calibration (2026-10-11, MacBook)

Thresholds were set against 291 renders from `Rich Structure.evolvfamily`
and 35 synthetic images (leopard spots, blobs, marbling, fBm clouds,
static, gradients, plain halves and quadrants).

- Synthetic: static and flat images are duds; ramps, gradients, blobs and
  fBm score 0.05-0.22; leopard spots 0.30-0.57; contour marbling of large
  blobs 0.66-0.73 (it is a contour map, so some structure is fair). Before
  variety moved to 64 px tiles and active pairs only, leopard spots scored
  0.79-0.85.
- Family renders: the butterfly lineage, the colour flow fields and the
  black-and-white arcs rank top (0.85-0.99); the grey marbling textures
  and noisy grain rank 0.2-0.5; flat or clipped images rank bottom.
- The family's starred and explored members don't separate from the rest
  (AUC about 0.5 on every component). They were picked by eye among close
  siblings, which these metrics aren't meant to tell apart.
- Vision's aesthetics score likes bright, colourful images and dislikes
  dark ones, which is roughly right, but it is noisy on abstract images,
  so it stays at 20% of the score.

### Retune after the first scorer-driven hunt (2026-10-11)

The first hunt ("Scorer Hunt": 57 random roots, 5 generations bred from
the top 4 overall) collapsed onto one grey contour-marbling lineage, with
good images saturating at 0.95-0.98, and a lineage that was mostly a plain
white gradient with a seam still scored 0.96. Changes:

- A tile now needs a mean |gradient| of 0.01-0.04 (was 0.004-0.02) to count
  as detail, so smooth gradients no longer count toward coverage.
- Mappings widened: coverage 0.2-0.9 (was raw), variety 0.18-0.42 (was
  0.15-0.33), coherence 0.35-0.70 (was 0.40-0.85; coherence only needs to
  separate lines from speckle, and higher isn't better), richness
  0.55-1.0 (was 0.45-0.90).
- Weights: coverage 0.2, variety 0.35, coherence 0.15, richness 0.3.

Now: butterflies about 0.91, contour marbling 0.83, the seam images
0.62-0.72, synthetic leopard spots 0.12-0.22, marbling of large blobs 0.37,
fBm clouds 0.15.

The second hunt ("Scorer Hunt 2", same roots, novelty penalty and at most
two parents per lineage) kept four lineages alive for all five
generations, and its nine finalists come from five lineages. Lineages
whose children never beat the parent get re-picked unchanged, which a
driver could treat as "stalled" and replace with a fresh root.

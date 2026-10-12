//
//  StructureAnalyzer.swift
//  EvolvScorer
//
//  Hand-made "rich structure, not leopard spots" metrics over the 256x256
//  luminance copy. See Documentation/Scorer.md for what each one is for.
//

import Foundation

struct StructureMetrics: Codable {
    /// Combined 0...1 structure score (0 for a dud).
    var score: Double
    /// Mapped 0...1 components that make up `score`.
    var coverage: Double
    var variety: Double
    var coherence: Double
    var richness: Double
    /// Raw measurements, for tuning and the dud filter.
    var raw: Raw

    struct Raw: Codable {
        /// Largest per-channel standard deviation.
        var contrast: Double
        /// Share of pixels with luminance below 0.02 or above 0.98.
        var clipped: Double
        /// Share of band-pass energy in the finest band (1 px detail).
        var fineEnergy: Double
        /// Share of band-pass energy per band, finest first.
        var bandEnergy: [Double]
        /// Mean pairwise tile descriptor distance, 0...1.
        var variety: Double
        /// Energy-weighted structure-tensor coherence, 0...1.
        var coherence: Double
        /// Normalised entropy of `bandEnergy`, 0...1.
        var richness: Double
        /// Share of tiles with real gradient energy (soft count).
        var coverage: Double
    }

    var dudReason: String?
}

enum StructureAnalyzer {
    /// Grid for coverage (8x8 tiles of 32 px) and for variety (4x4 of 64 px).
    static let coverageTiles = 8
    static let varietyTiles = 4
    /// Blur sigmas (px at 256) separating the band-pass levels; band k is
    /// blur(sigma[k-1]) - blur(sigma[k]), with sigma 0 being the image itself.
    static let bandSigmas: [Float] = [1, 2, 4, 8, 16]
    /// Mean |gradient| per tile (luminance units per px at 256) that counts
    /// as "has detail": soft between these two.
    static let activeTile: (Double, Double) = (0.01, 0.04)

    static func analyze(_ image: AnalysisImage) -> StructureMetrics {
        let w = image.width, h = image.height, n = w * h
        let lum = image.luminance

        // Contrast and clipping.
        let contrast = [image.red, image.green, image.blue].map(standardDeviation).max() ?? 0
        var clippedCount = 0
        for v in lum where v < 0.02 || v > 0.98 { clippedCount += 1 }
        let clipped = Double(clippedCount) / Double(n)

        // Band-pass pyramid by incremental Gaussian blurs.
        var levels: [[Float]] = [lum]
        var previousSigma: Float = 0
        for sigma in bandSigmas {
            let step = (sigma * sigma - previousSigma * previousSigma).squareRoot()
            levels.append(gaussianBlur(levels.last!, width: w, height: h, sigma: step))
            previousSigma = sigma
        }
        var bands: [[Float]] = []
        for k in 0..<bandSigmas.count {
            bands.append(zip(levels[k], levels[k + 1]).map { $0 - $1 })
        }
        let bandTotals = bands.map { band in band.reduce(0.0) { $0 + Double($1 * $1) } }
        let bandEnergy = normalised(bandTotals)
        let richnessRaw = entropy(bandEnergy) / log(Double(bandEnergy.count))
        let fineEnergy = bandEnergy.first ?? 0

        // Gradients (central differences, edges clamped).
        var gx = [Float](repeating: 0, count: n)
        var gy = gx
        for y in 0..<h {
            let up = max(y - 1, 0), down = min(y + 1, h - 1)
            for x in 0..<w {
                let left = max(x - 1, 0), right = min(x + 1, w - 1)
                gx[y * w + x] = (lum[y * w + right] - lum[y * w + left]) * 0.5
                gy[y * w + x] = (lum[down * w + x] - lum[up * w + x]) * 0.5
            }
        }

        // Structure tensor coherence, weighted by local edge energy.
        let jxx = gaussianBlur(gx.map { $0 * $0 }, width: w, height: h, sigma: 2)
        let jyy = gaussianBlur(gy.map { $0 * $0 }, width: w, height: h, sigma: 2)
        let jxy = gaussianBlur(zip(gx, gy).map { $0 * $1 }, width: w, height: h, sigma: 2)
        var coherenceSum = 0.0, coherenceWeight = 0.0
        for i in 0..<n {
            let trace = Double(jxx[i] + jyy[i])
            guard trace > 1e-12 else { continue }
            let diff = Double(jxx[i] - jyy[i])
            let anisotropy = (diff * diff + 4 * Double(jxy[i] * jxy[i])).squareRoot()
            coherenceSum += anisotropy
            coherenceWeight += trace
        }
        let coherenceRaw = coherenceWeight > 0 ? coherenceSum / coherenceWeight : 0

        // Coverage on the fine grid: how much of the image has detail at all.
        let fine = tileDescriptors(tiles: coverageTiles, gx: gx, gy: gy, bands: bands, width: w, height: h)
        let coverageRaw = fine.activity.reduce(0, +) / Double(fine.activity.count)

        // Variety on the coarse grid, between tiles that have detail. Tiles
        // big enough to hold several spots make a stationary texture (leopard
        // spots, marbling, static) look the same everywhere; pairing only
        // active tiles stops "spot edge vs empty background" reading as variety.
        let coarse = tileDescriptors(tiles: varietyTiles, gx: gx, gy: gy, bands: bands, width: w, height: h)
        var distanceSum = 0.0, weightSum = 0.0
        let energyFloor = 0.001
        for i in 0..<coarse.energy.count {
            for j in (i + 1)..<coarse.energy.count {
                let weight = coarse.activity[i] * coarse.activity[j]
                guard weight > 0 else { continue }
                let orientation = halfL1(coarse.orientation[i], coarse.orientation[j])
                let scale = halfL1(coarse.bands[i], coarse.bands[j])
                let energy = min(1, abs(log((coarse.energy[i] + energyFloor) / (coarse.energy[j] + energyFloor))) / log(8))
                distanceSum += weight * (orientation + scale + energy) / 3
                weightSum += weight
            }
        }
        let varietyRaw = weightSum > 0 ? distanceSum / weightSum : 0

        let raw = StructureMetrics.Raw(
            contrast: contrast, clipped: clipped, fineEnergy: fineEnergy,
            bandEnergy: bandEnergy, variety: varietyRaw, coherence: coherenceRaw,
            richness: richnessRaw, coverage: coverageRaw)
        return combine(raw)
    }

    // MARK: - Mapping and the dud filter

    static func combine(_ raw: StructureMetrics.Raw) -> StructureMetrics {
        let coverage = smoothstep(0.20, 0.90, raw.coverage)
        let variety = smoothstep(0.18, 0.42, raw.variety)
        let coherence = smoothstep(0.35, 0.70, raw.coherence)
        let richness = smoothstep(0.55, 1.00, raw.richness)

        var dudReason: String?
        if raw.contrast < 0.03 {
            dudReason = "flat"
        } else if raw.clipped > 0.97 {
            dudReason = "clipped"
        } else if raw.fineEnergy > 0.6 && raw.coherence < 0.25 {
            dudReason = "static"
        }

        // Weighted geometric mean, so an image has to do reasonably on every
        // axis; the floor keeps one zero from erasing everything else.
        let parts: [(Double, Double)] = [(coverage, 0.2), (variety, 0.35), (coherence, 0.15), (richness, 0.3)]
        let floor = 0.02
        var score = exp(parts.reduce(0) { $0 + $1.1 * log(max($1.0, floor)) })
        if dudReason != nil { score = 0 }

        return StructureMetrics(
            score: score, coverage: coverage, variety: variety,
            coherence: coherence, richness: richness, raw: raw, dudReason: dudReason)
    }

    // MARK: - Tiles

    struct TileDescriptors {
        /// Mean |gradient| per tile.
        var energy: [Double]
        /// Soft "has detail" per tile, 0...1.
        var activity: [Double]
        /// Gradient-energy-weighted orientation histogram per tile (8 bins over the doubled angle).
        var orientation: [[Double]]
        /// Band-pass energy distribution per tile.
        var bands: [[Double]]
    }

    static func tileDescriptors(tiles: Int, gx: [Float], gy: [Float], bands: [[Float]], width w: Int, height h: Int) -> TileDescriptors {
        let tileSize = w / tiles, count = tiles * tiles
        let orientationBins = 8
        var energy = [Double](repeating: 0, count: count)
        var orientation = [[Double]](repeating: [Double](repeating: 0, count: orientationBins), count: count)
        var bandEnergy = [[Double]](repeating: [Double](repeating: 0, count: bands.count), count: count)
        for y in 0..<h {
            let ty = min(y / tileSize, tiles - 1)
            for x in 0..<w {
                let t = ty * tiles + min(x / tileSize, tiles - 1)
                let i = y * w + x
                let gxx = Double(gx[i]), gyy = Double(gy[i])
                let magnitudeSquared = gxx * gxx + gyy * gyy
                energy[t] += magnitudeSquared.squareRoot()
                // Doubled angle, so opposite gradient directions share a bin.
                let angle = atan2(2 * gxx * gyy, gxx * gxx - gyy * gyy)
                let bin = min(Int((angle + .pi) / (2 * .pi) * Double(orientationBins)), orientationBins - 1)
                orientation[t][bin] += magnitudeSquared
                for k in 0..<bands.count {
                    bandEnergy[t][k] += Double(bands[k][i] * bands[k][i])
                }
            }
        }
        let pixelsPerTile = Double(tileSize * tileSize)
        var activity = [Double](repeating: 0, count: count)
        for t in 0..<count {
            energy[t] /= pixelsPerTile
            activity[t] = smoothstep(activeTile.0, activeTile.1, energy[t])
            orientation[t] = normalised(orientation[t])
            bandEnergy[t] = normalised(bandEnergy[t])
        }
        return TileDescriptors(energy: energy, activity: activity, orientation: orientation, bands: bandEnergy)
    }

    // MARK: - Helpers

    static func gaussianBlur(_ input: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }

        var horizontal = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum: Float = 0
                for k in -radius...radius {
                    let sx = min(max(x + k, 0), width - 1)
                    sum += input[row + sx] * kernel[k + radius]
                }
                horizontal[row + x] = sum
            }
        }
        var output = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for k in -radius...radius {
                    let sy = min(max(y + k, 0), height - 1)
                    sum += horizontal[sy * width + x] * kernel[k + radius]
                }
                output[y * width + x] = sum
            }
        }
        return output
    }

    static func standardDeviation(_ values: [Float]) -> Double {
        let n = Double(values.count)
        let mean = values.reduce(0.0) { $0 + Double($1) } / n
        let variance = values.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / n
        return variance.squareRoot()
    }

    static func normalised(_ values: [Double]) -> [Double] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 1 / Double(values.count) } }
        return values.map { $0 / total }
    }

    static func entropy(_ p: [Double]) -> Double {
        -p.reduce(0) { $0 + ($1 > 0 ? $1 * log($1) : 0) }
    }

    static func halfL1(_ a: [Double], _ b: [Double]) -> Double {
        0.5 * zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

//
//  AnalysisImage.swift
//  EvolvScorer
//
//  Decodes an image and reduces it to the fixed size the structure metrics
//  work at, so scores don't depend on the render's resolution.
//

import CoreGraphics
import Foundation
import ImageIO

struct AnalysisImage {
    /// Width and height of the analysis copy, in pixels. 8x8 tiles of 32 px.
    static let size = 256

    let width: Int
    let height: Int
    /// sRGB channel values, row-major, 0...1.
    let red: [Float]
    let green: [Float]
    let blue: [Float]
    /// Rec. 709 weights over the sRGB values (not linearised; the metrics
    /// care about perceived edges, not physical light).
    let luminance: [Float]

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func decode(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    init?(_ image: CGImage) {
        let size = Self.size
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }

        let count = size * size
        var r = [Float](repeating: 0, count: count)
        var g = r, b = r, l = r
        for i in 0..<count {
            let rv = Float(pixels[i * 4]) / 255
            let gv = Float(pixels[i * 4 + 1]) / 255
            let bv = Float(pixels[i * 4 + 2]) / 255
            r[i] = rv
            g[i] = gv
            b[i] = bv
            l[i] = 0.2126 * rv + 0.7152 * gv + 0.0722 * bv
        }
        width = size
        height = size
        red = r
        green = g
        blue = b
        luminance = l
    }
}

//
//  MCPRenderTool.swift
//  Evolv.io
//
//  The MCP `render` tool: renders an expression (or one of the app's
//  genotypes, see GenotypeStore) through the same Parser -> Metal ->
//  CGImage path the app uses on screen, and returns PNGs as MCP image
//  content -- optionally side by side with one of Sims' original figures
//  (bundled from Documentation/OriginalFigure*.gif) at the same size and
//  framing, plus zoomed crops of both. Exists because the app's sandboxed container is
//  otherwise unreadable from outside the app (see Documentation/MCPServer.md).
//

import CoreGraphics
import Foundation
import ImageIO
import MCP
import ExpressionTree

enum MCPRenderTool {
    /// Largest width or height accepted for any single rendered image.
    private static let maxDimension = 4096
    private static let sideBySideGap = 8

    static let tool = Tool(
        name: "render",
        description: """
        Renders an Evolv.io expression to a PNG via the app's own Parser + Metal renderer \
        (same color mapping as the on-screen view: each channel clamped to 0...1). Pass either \
        `expression` or `sample` (a genotype from the app's sidebar, by name or file id, e.g. "Figure 9"). \
        With `reference` ("Figure 9", "Figure 10" or "Figure 12"), returns our render and Sims' \
        original side by side (ours left, original right) at the same size, and the framing \
        defaults to the original's aspect ratio by cropping the app's -1...1 square (for these wide figures: x from -1 to 1, top and bottom cut off, as in the paper). \
        `crops` adds zoomed re-renders of given coordinate regions (paired with the matching \
        crop of the original when a reference is given).
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "expression": .object([
                    "type": .string("string"),
                    "description": .string("S-expression to render, e.g. \"(color-grad x 3.1 1.86 #(0.95 0.7 0.59) 1.35)\"."),
                ]),
                "sample": .object([
                    "type": .string("string"),
                    "description": .string("A genotype from the app's sidebar (bundled or user .evolvgenotype), matched case-insensitively by display name or file id, e.g. \"Figure 9\" or \"11-figure-9\". Ignored if `expression` is given."),
                ]),
                "reference": .object([
                    "type": .string("string"),
                    "description": .string("Original figure to compare against: \"Figure 9\", \"Figure 10\" or \"Figure 12\"."),
                ]),
                "width": .object([
                    "type": .string("integer"),
                    "description": .string("Output width in pixels. Defaults to the reference's width, else derived from `height` and the x/y range, else 512 tall."),
                ]),
                "height": .object([
                    "type": .string("integer"),
                    "description": .string("Output height in pixels. Defaults like `width`."),
                ]),
                "x_min": .object(["type": .string("number"), "description": .string("Left edge in expression coordinates. Default: the -1...1 square cropped to the output aspect (reference's width/height, else width/height, else 1) -- i.e. -1 for wide images, -aspect for tall ones.")]),
                "x_max": .object(["type": .string("number"), "description": .string("Right edge. Default: mirror of x_min.")]),
                "y_min": .object(["type": .string("number"), "description": .string("Bottom edge. Default -1/aspect for wide images, -1 for tall ones.")]),
                "y_max": .object(["type": .string("number"), "description": .string("Top edge. Default: mirror of y_min.")]),
                "supersample": .object([
                    "type": .string("integer"),
                    "description": .string("Samples per pixel along each axis (1-8). Default 4, matching the app's Supersampling setting."),
                ]),
                "crops": .object([
                    "type": .string("array"),
                    "description": .string("Zoomed regions, each re-rendered at `width` pixels wide (height from the region's aspect)."),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "x_min": .object(["type": .string("number")]),
                            "x_max": .object(["type": .string("number")]),
                            "y_min": .object(["type": .string("number")]),
                            "y_max": .object(["type": .string("number")]),
                        ]),
                        "required": .array([.string("x_min"), .string("x_max"), .string("y_min"), .string("y_max")]),
                    ]),
                ]),
            ]),
        ])
    )

    struct Failure: Error {
        let message: String
    }

    static func call(arguments: [String: MCP.Value]?) async -> CallTool.Result {
        do {
            return try await render(arguments: arguments ?? [:])
        } catch let failure as Failure {
            return errorResult(failure.message)
        } catch {
            return errorResult("render failed: \(error.localizedDescription)")
        }
    }

    private static func render(arguments args: [String: MCP.Value]) async throws -> CallTool.Result {
        // Expression
        let (expression, label) = try await expression(from: args, tool: "render")

        let node: any Node
        do {
            node = try Parser().parse(expression)
        } catch {
            throw Failure(message: "Failed to parse \(label): \(error)")
        }

        // Reference
        var reference: Reference?
        if case .string(let name)? = args["reference"] {
            reference = try loadReference(named: name)
        }

        // Framing
        let requestedWidth = try integer(args["width"], "width")
        let requestedHeight = try integer(args["height"], "height")
        let aspect: Double
        if let reference {
            aspect = Double(reference.image.width) / Double(reference.image.height)
        } else if let requestedWidth, let requestedHeight {
            aspect = Double(requestedWidth) / Double(requestedHeight)
        } else {
            aspect = 1
        }
        // Crop the app's -1...1 square to the aspect rather than widening
        // it: Sims' published figures cut off the top and bottom.
        let defaultFraming = reference?.framing ?? croppedSquare(aspect: aspect)
        let xMin = try number(args["x_min"], "x_min") ?? defaultFraming.minX
        let xMax = try number(args["x_max"], "x_max") ?? defaultFraming.maxX
        let yMin = try number(args["y_min"], "y_min") ?? defaultFraming.minY
        let yMax = try number(args["y_max"], "y_max") ?? defaultFraming.maxY
        guard xMax > xMin, yMax > yMin else {
            throw Failure(message: "x_max must exceed x_min and y_max must exceed y_min.")
        }
        let bounds = CGRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin)
        let boundsAspect = bounds.width / bounds.height

        let width: Int
        let height: Int
        switch (requestedWidth, requestedHeight) {
            case let (w?, h?):
                (width, height) = (w, h)
            case let (w?, nil):
                (width, height) = (w, Int((Double(w) / boundsAspect).rounded()))
            case let (nil, h?):
                (width, height) = (Int((Double(h) * boundsAspect).rounded()), h)
            case (nil, nil):
                if let reference {
                    (width, height) = (reference.image.width, reference.image.height)
                } else {
                    (width, height) = (Int((512 * boundsAspect).rounded()), 512)
                }
        }
        try validate(width: width, height: height)

        let supersample = try integer(args["supersample"], "supersample") ?? 4
        guard (1...8).contains(supersample) else {
            throw Failure(message: "supersample must be between 1 and 8.")
        }

        var crops: [CGRect] = []
        if let cropsArg = args["crops"] {
            guard case .array(let items) = cropsArg else {
                throw Failure(message: "crops must be an array of {x_min, x_max, y_min, y_max} objects.")
            }
            for (index, item) in items.enumerated() {
                guard case .object(let region) = item,
                      let cx0 = try number(region["x_min"], "crops[\(index)].x_min"),
                      let cx1 = try number(region["x_max"], "crops[\(index)].x_max"),
                      let cy0 = try number(region["y_min"], "crops[\(index)].y_min"),
                      let cy1 = try number(region["y_max"], "crops[\(index)].y_max"),
                      cx1 > cx0, cy1 > cy0 else {
                    throw Failure(message: "crops[\(index)] needs numeric x_min < x_max and y_min < y_max.")
                }
                crops.append(CGRect(x: cx0, y: cy0, width: cx1 - cx0, height: cy1 - cy0))
            }
        }

        // Main render
        let main = try renderImage(node: node, bounds: bounds, width: width, height: height, supersample: supersample)
        var content: [Tool.Content] = []
        var summary = """
        Rendered \(label) at \(width)x\(height), supersample \(supersample), \
        x \(xMin)...\(xMax), y \(yMin)...\(yMax). \
        Raw output range: min \(format(main.minValue)), max \(format(main.maxValue)) (display clamps each channel to 0...1).
        """
        if let reference {
            summary += "\nLeft: our render. Right: original \(reference.name) (\(reference.image.width)x\(reference.image.height)) scaled to \(width)x\(height)."
            content.append(.text(text: summary, annotations: nil, _meta: nil))
            content.append(try png(sideBySide(main.image, reference.image, width: width, height: height)))
        } else {
            content.append(.text(text: summary, annotations: nil, _meta: nil))
            content.append(try png(main.image))
        }

        // Crops: re-rendered at full resolution, not upscaled
        for (index, crop) in crops.enumerated() {
            let cropWidth = width
            let cropHeight = Int((Double(cropWidth) * crop.height / crop.width).rounded())
            try validate(width: cropWidth, height: cropHeight)
            let rendered = try renderImage(node: node, bounds: crop, width: cropWidth, height: cropHeight, supersample: supersample)
            var text = "Crop \(index): x \(crop.minX)...\(crop.maxX), y \(crop.minY)...\(crop.maxY), \(cropWidth)x\(cropHeight)."
            if let reference, let referenceCrop = cropReference(reference.image, to: crop, within: reference.framing) {
                text += " Left: our re-render. Right: the same region of the original, upscaled."
                content.append(.text(text: text, annotations: nil, _meta: nil))
                content.append(try png(sideBySide(rendered.image, referenceCrop, width: cropWidth, height: cropHeight)))
            } else {
                if reference != nil {
                    text += " (Region lies outside the original's framing; no reference crop.)"
                }
                content.append(.text(text: text, annotations: nil, _meta: nil))
                content.append(try png(rendered.image))
            }
        }

        return CallTool.Result(content: content)
    }

    /// `expression`, or else the sidebar genotype named by `sample`, with a
    /// label for messages. Shared with `mutate_genotype`.
    static func expression(from args: [String: MCP.Value], tool: String) async throws -> (expression: String, label: String) {
        if case .string(let text)? = args["expression"] {
            return (text, "expression")
        }
        guard case .string(let name)? = args["sample"] else {
            throw Failure(message: "\(tool) requires a string argument \"expression\" or \"sample\".")
        }
        let genotypes = await MainActor.run { GenotypeStore.shared.genotypes }
        let matches = { (genotype: Genotype) in
            genotype.displayName.caseInsensitiveCompare(name) == .orderedSame
                || genotype.id.caseInsensitiveCompare(name) == .orderedSame
        }
        guard let match = genotypes.first(where: matches) else {
            let available = genotypes.map { $0.name ?? $0.id }
            throw Failure(message: "No genotype named \"\(name)\". Available: \(available.joined(separator: ", "))")
        }
        return (match.expression, "genotype \"\(match.displayName)\"")
    }

    // MARK: - Rendering

    static func renderImage(node: any Node, bounds: CGRect, width: Int, height: Int, supersample: Int) throws -> (image: CGImage, minValue: SIMD3<Double>, maxValue: SIMD3<Double>) {
        let evaluator = Evaluator(size: CGSize(width: width, height: height))
        let data = try evaluator.render(node: node, bounds: bounds, supersample: supersample)
        var minValue = SIMD3<Double>(repeating: .infinity)
        var maxValue = SIMD3<Double>(repeating: -.infinity)
        for pixel in data {
            minValue = pointwiseMin(minValue, pixel)
            maxValue = pointwiseMax(maxValue, pixel)
        }
        guard let image = NodeRenderer.cgImage(data: data, width: width, height: height) else {
            throw Failure(message: "Failed to build an image from the render output.")
        }
        return (image, minValue, maxValue)
    }

    // MARK: - Reference figures

    private struct Reference {
        let name: String
        let image: CGImage
        /// The expression-coordinate rectangle the original shows.
        let framing: CGRect
    }

    /// Per-figure correction to `croppedSquare`: the scanned originals
    /// aren't perfectly centered/scaled on the origin. Figure 9's values
    /// were measured by edge cross-correlation against our render (~4px
    /// offset at 464x367, best match with the framing ~2% tighter); the others are
    /// uncalibrated until our renders resemble them closely enough to measure.
    private static let referenceAlignment: [String: (offset: CGPoint, zoom: Double)] = [
        "9": (CGPoint(x: 0.0172, y: 0.0172), 0.98),
        "10": (.zero, 1),
        "12": (.zero, 1),
    ]

    /// The app's -1...1 square cropped (never widened) to `aspect` --
    /// Sims' published figures cut off the top and bottom.
    static func croppedSquare(aspect: Double) -> CGRect {
        let halfWidth = min(1, aspect)
        let halfHeight = min(1, 1 / aspect)
        return CGRect(x: -halfWidth, y: -halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
    }

    /// Accepts "Figure 9", "figure9", "9", "OriginalFigure9", "OriginalFigure9.gif".
    private static func loadReference(named rawName: String) throws -> Reference {
        let digits = rawName.filter(\.isNumber)
        guard let alignment = referenceAlignment[digits] else {
            throw Failure(message: "Unknown reference \"\(rawName)\". Available: \(referenceAlignment.keys.sorted { Int($0)! < Int($1)! }.map { "Figure \($0)" }.joined(separator: ", ")).")
        }
        guard let url = Bundle.main.url(forResource: "OriginalFigure\(digits)", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(message: "OriginalFigure\(digits).gif is missing from the app bundle.")
        }
        let square = croppedSquare(aspect: Double(image.width) / Double(image.height))
        let halfWidth = square.width / 2 * alignment.zoom
        let halfHeight = square.height / 2 * alignment.zoom
        let framing = CGRect(x: alignment.offset.x - halfWidth, y: alignment.offset.y - halfHeight,
                             width: 2 * halfWidth, height: 2 * halfHeight)
        return Reference(name: "Figure \(digits)", image: image, framing: framing)
    }

    /// The part of `reference` (which spans `framing`) covering `region`,
    /// or nil if the two don't overlap.
    private static func cropReference(_ reference: CGImage, to region: CGRect, within framing: CGRect) -> CGImage? {
        let scaleX = Double(reference.width) / framing.width
        let scaleY = Double(reference.height) / framing.height
        // Image rows run top-down; y runs bottom-up.
        let pixelRect = CGRect(x: (region.minX - framing.minX) * scaleX,
                               y: (framing.maxY - region.maxY) * scaleY,
                               width: region.width * scaleX,
                               height: region.height * scaleY).integral
        let clipped = pixelRect.intersection(CGRect(x: 0, y: 0, width: reference.width, height: reference.height))
        guard !clipped.isEmpty else { return nil }
        return reference.cropping(to: clipped)
    }

    // MARK: - Compositing

    private static func sideBySide(_ left: CGImage, _ right: CGImage, width: Int, height: Int) throws -> CGImage {
        let totalWidth = width * 2 + sideBySideGap
        guard let context = CGContext(data: nil, width: totalWidth, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure(message: "Failed to create a compositing context.")
        }
        context.interpolationQuality = .high
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: height))
        context.draw(left, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(right, in: CGRect(x: width + sideBySideGap, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw Failure(message: "Failed to composite the side-by-side image.")
        }
        return image
    }

    static func png(_ image: CGImage) throws -> Tool.Content {
        guard let data = image.pngData() else {
            throw Failure(message: "Failed to encode PNG.")
        }
        return .image(data: data.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil)
    }

    // MARK: - Argument helpers

    private static func validate(width: Int, height: Int) throws {
        guard (1...maxDimension).contains(width), (1...maxDimension).contains(height) else {
            throw Failure(message: "Image size \(width)x\(height) is out of range (1...\(maxDimension) per side).")
        }
    }

    private static func number(_ value: MCP.Value?, _ name: String) throws -> Double? {
        switch value {
            case nil, .null?: return nil
            case .double(let d)?: return d
            case .int(let i)?: return Double(i)
            case .string(let s)?:
                if let d = Double(s) { return d }
                fallthrough
            default: throw Failure(message: "\(name) must be a number.")
        }
    }

    private static func integer(_ value: MCP.Value?, _ name: String) throws -> Int? {
        guard let d = try number(value, name) else { return nil }
        guard d == d.rounded() else { throw Failure(message: "\(name) must be an integer.") }
        return Int(d)
    }

    private static func format(_ v: SIMD3<Double>) -> String {
        "(" + [v.x, v.y, v.z].map { String(format: "%.3g", $0) }.joined(separator: ", ") + ")"
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}

//
//  MCPRenderGridTool.swift
//  Evolv.io
//
//  The MCP `render_grid` tool: renders several expressions into one
//  numbered contact sheet, like Sims' Figure 5 (a parent and 19 mutated
//  children). Made for looking at a generation from `mutate_genotype` or
//  a batch from `generate_genotypes` in one image.
//

import AppKit
import CoreGraphics
import Foundation
import MCP
import ExpressionTree

enum MCPRenderGridTool {
    private static let maxCount = 100
    private static let maxDimension = 8192
    private static let gap = 4

    static let tool = Tool(
        name: "render_grid",
        description: """
        Renders a list of expressions into one PNG contact sheet, left to right and top to \
        bottom, each cell numbered from 0 in its top-left corner. Each cell shows the app's \
        -1...1 square cropped to the cell's aspect, colours clamped to 0...1 as on screen. An \
        expression that fails to parse or render is a grey cell, listed in the text. For a \
        generation from mutate_genotype, pass the parent first so it's cell 0.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "expressions": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("S-expressions to render, 1-\(maxCount)."),
                ]),
                "columns": .object([
                    "type": .string("integer"),
                    "description": .string("Cells per row. Default 5 (Sims' 5x4 grid for a parent and 19 children), or fewer if there are fewer expressions."),
                ]),
                "cell_width": .object([
                    "type": .string("integer"),
                    "description": .string("Cell width in pixels. Default 200."),
                ]),
                "cell_height": .object([
                    "type": .string("integer"),
                    "description": .string("Cell height in pixels. Default: cell_width."),
                ]),
                "supersample": .object([
                    "type": .string("integer"),
                    "description": .string("Samples per pixel along each axis (1-8). Default 2."),
                ]),
                "numbers": .object([
                    "type": .string("boolean"),
                    "description": .string("Draw each cell's index in its corner. Default true."),
                ]),
            ]),
            "required": .array([.string("expressions")]),
        ])
    )

    private struct Failure: Error {
        let message: String
    }

    static func call(arguments: [String: MCP.Value]?) async -> CallTool.Result {
        do {
            return try render(arguments: arguments ?? [:])
        } catch let failure as Failure {
            return errorResult(failure.message)
        } catch let failure as MCPRenderTool.Failure {
            return errorResult(failure.message)
        } catch {
            return errorResult("render_grid failed: \(error.localizedDescription)")
        }
    }

    private static func render(arguments args: [String: MCP.Value]) throws -> CallTool.Result {
        guard case .array(let values)? = args["expressions"] else {
            throw Failure(message: "render_grid requires an array argument \"expressions\".")
        }
        let expressions = try values.map { value -> String in
            guard case .string(let text) = value else { throw Failure(message: "expressions must all be strings.") }
            return text
        }
        guard (1...maxCount).contains(expressions.count) else {
            throw Failure(message: "expressions must have 1-\(maxCount) entries.")
        }

        let columns = min(expressions.count, try integer(args["columns"], "columns") ?? 5)
        guard columns >= 1 else { throw Failure(message: "columns must be at least 1.") }
        let rows = (expressions.count + columns - 1) / columns
        let cellWidth = try integer(args["cell_width"], "cell_width") ?? 200
        let cellHeight = try integer(args["cell_height"], "cell_height") ?? cellWidth
        guard cellWidth >= 16, cellHeight >= 16 else { throw Failure(message: "Cells must be at least 16 pixels each way.") }
        let supersample = try integer(args["supersample"], "supersample") ?? 2
        guard (1...8).contains(supersample) else { throw Failure(message: "supersample must be between 1 and 8.") }
        var numbers = true
        if case .bool(let flag)? = args["numbers"] { numbers = flag }

        let totalWidth = columns * cellWidth + (columns - 1) * gap
        let totalHeight = rows * cellHeight + (rows - 1) * gap
        guard totalWidth <= maxDimension, totalHeight <= maxDimension else {
            throw Failure(message: "The sheet would be \(totalWidth)x\(totalHeight); the limit is \(maxDimension) per side. Use smaller cells or fewer columns.")
        }
        guard let context = CGContext(data: nil, width: totalWidth, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure(message: "Failed to create a compositing context.")
        }
        context.setFillColor(gray: 0.15, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        let bounds = MCPRenderTool.croppedSquare(aspect: Double(cellWidth) / Double(cellHeight))
        var problems: [String] = []
        for (index, expression) in expressions.enumerated() {
            let column = index % columns
            let row = index / columns
            // Core Graphics' origin is bottom-left; row 0 is the top row.
            let cell = CGRect(x: column * (cellWidth + gap),
                              y: totalHeight - (row + 1) * cellHeight - row * gap,
                              width: cellWidth, height: cellHeight)
            do {
                let node = try Parser().parse(expression)
                let rendered = try MCPRenderTool.renderImage(node: node, bounds: bounds, width: cellWidth, height: cellHeight, supersample: supersample)
                context.draw(rendered.image, in: cell)
            } catch {
                let message = (error as? MCPRenderTool.Failure)?.message ?? error.localizedDescription
                problems.append("\(index): \(message)")
                context.setFillColor(gray: 0.5, alpha: 1)
                context.fill(cell)
            }
            if numbers {
                drawNumber(index, in: cell, context: context)
            }
        }

        guard let image = context.makeImage() else {
            throw Failure(message: "Failed to composite the grid.")
        }
        var summary = "\(expressions.count) expressions in \(columns) columns, \(cellWidth)x\(cellHeight) cells, supersample \(supersample), x \(bounds.minX)...\(bounds.maxX), y \(bounds.minY)...\(bounds.maxY)."
        if !problems.isEmpty {
            summary += "\nFailed (grey cells):\n" + problems.joined(separator: "\n")
        }
        return CallTool.Result(content: [
            .text(text: summary, annotations: nil, _meta: nil),
            try MCPRenderTool.png(image),
        ])
    }

    /// White on a dark rounded tab, top-left of the cell, readable on any
    /// image.
    private static func drawNumber(_ number: Int, in cell: CGRect, context: CGContext) {
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        let tab = CGRect(x: cell.minX + 3, y: cell.maxY - size.height - 7,
                         width: size.width + 8, height: size.height + 4)
        context.saveGState()
        context.setFillColor(gray: 0, alpha: 0.6)
        context.addPath(CGPath(roundedRect: tab, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: tab.minX + 4, y: tab.minY + 2))
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func integer(_ value: MCP.Value?, _ name: String) throws -> Int? {
        switch value {
            case nil, .null?: return nil
            case .int(let int)?: return int
            case .double(let double)? where double == double.rounded(): return Int(double)
            default: throw Failure(message: "\(name) must be an integer.")
        }
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}

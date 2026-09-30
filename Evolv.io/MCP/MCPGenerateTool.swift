//
//  MCPGenerateTool.swift
//  Evolv.io
//
//  The MCP `generate_genotypes` tool: random genotypes from
//  RandomExpressionGenerator, the same way the main window's grid makes
//  them (see RandomGridView.generate()). Returns expressions only; render
//  them with the `render` tool.
//

import Foundation
import MCP
import ExpressionTree

enum MCPGenerateTool {
    private static let maxCount = 100

    static let tool = Tool(
        name: "generate_genotypes",
        description: """
        Generates random genotypes with RandomExpressionGenerator, exactly as the main window's \
        grid does, and returns them as JSON (seed, max_depth, and the expressions in order). \
        The same seed and settings give the same expressions; seed with count 9 and the grid's \
        depth reproduces a grid whose seed is shown in the window subtitle. Render the \
        expressions with the `render` tool.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "seed": .object([
                    "type": .array([.string("integer"), .string("string")]),
                    "description": .string("UInt64 seed, as an integer or a decimal string (seeds above 2^53 must be strings to survive JSON). Default: random."),
                ]),
                "count": .object([
                    "type": .string("integer"),
                    "description": .string("How many genotypes to generate from the seed, 1-\(maxCount). Default 9."),
                ]),
                "max_depth": .object([
                    "type": .string("integer"),
                    "description": .string("Deepest nesting of function calls (the grid's Depth stepper). Default 10."),
                ]),
                "exclude": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Node names never picked as functions. Default none."),
                ]),
            ]),
        ])
    )

    private struct Failure: Error {
        let message: String
    }

    static func call(arguments: [String: MCP.Value]?) async -> CallTool.Result {
        do {
            return try await generate(arguments: arguments ?? [:])
        } catch let failure as Failure {
            return errorResult(failure.message)
        } catch {
            return errorResult("generate_genotypes failed: \(error.localizedDescription)")
        }
    }

    private static func generate(arguments args: [String: MCP.Value]) async throws -> CallTool.Result {
        let seed: UInt64
        switch args["seed"] {
            case nil, .null?:
                seed = UInt64.random(in: 0...UInt64.max)
            case .int(let value)?:
                guard value >= 0 else { throw Failure(message: "seed must be non-negative.") }
                seed = UInt64(value)
            case .double(let value)?:
                guard value >= 0, value == value.rounded(), let exact = UInt64(exactly: value) else {
                    throw Failure(message: "seed must be a non-negative integer.")
                }
                seed = exact
            case .string(let text)?:
                guard let parsed = UInt64(text) else { throw Failure(message: "seed \"\(text)\" isn't a UInt64.") }
                seed = parsed
            default:
                throw Failure(message: "seed must be an integer or a decimal string.")
        }

        let count = try integer(args["count"], "count") ?? 9
        guard (1...maxCount).contains(count) else {
            throw Failure(message: "count must be 1-\(maxCount).")
        }

        var configuration = RandomExpressionGenerator.Configuration()
        if let maxDepth = try integer(args["max_depth"], "max_depth") {
            guard maxDepth >= 1 else { throw Failure(message: "max_depth must be at least 1.") }
            configuration.maxDepth = maxDepth
        }
        if let exclude = args["exclude"] {
            guard case .array(let values) = exclude else {
                throw Failure(message: "exclude must be an array of node names.")
            }
            configuration.excludedFunctions = Set(values.compactMap { value in
                if case .string(let name) = value { return name }
                return nil
            })
        }

        let signatures = NodeRegistry.shared.signatures
        let generator = RandomExpressionGenerator(signatures: signatures, configuration: configuration)
        var rng = SeededRandomNumberGenerator(seed: seed)
        let expressions = (0..<count).map { _ in generator.generate(using: &rng).description }

        let json: [String: Any] = [
            "seed": String(seed),
            "max_depth": configuration.maxDepth,
            "expressions": expressions,
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
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

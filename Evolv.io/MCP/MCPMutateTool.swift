//
//  MCPMutateTool.swift
//  Evolv.io
//
//  The MCP `mutate_genotype` tool: one generation of asexual reproduction.
//  Mutated children of one parent from ExpressionMutator (Sims' scheme, see
//  Documentation/Mutation.md), each with a log of what changed. Stateless:
//  evolving is calling it again on the child you pick. Render a generation
//  with `render_grid`.
//

import Foundation
import MCP
import ExpressionTree

enum MCPMutateTool {
    private static let maxCount = 100
    /// Redraws for a child the app's Parser won't build, before giving up.
    private static let maxParseRetries = 20

    static let tool = Tool(
        name: "mutate_genotype",
        description: """
        Makes mutated children of one parent genotype, the way Sims describes (1991 §4.2): each \
        node of the parent may mutate, with a chance scaled to about one mutation per child, into \
        a new random expression, an adjusted constant, a different function, a wrapped or hoisted \
        expression, or a copy of another part of the parent. Children that come out unchanged or \
        too big are redrawn. Returns JSON: seed, parent, and each child's expression with the \
        mutations that made it (kind, path of argument indices from the root, before, after). \
        The same seed and parent give the same children. Pass `[parent, ...children]` to \
        `render_grid` to see the generation; mutate a chosen child to continue.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "expression": .object([
                    "type": .string("string"),
                    "description": .string("The parent, as an s-expression."),
                ]),
                "sample": .object([
                    "type": .string("string"),
                    "description": .string("The parent as a genotype from the app's sidebar, by display name or file id (like `render`). Ignored if `expression` is given."),
                ]),
                "count": .object([
                    "type": .string("integer"),
                    "description": .string("How many children, 1-\(maxCount). Default 19, as in Sims' figures."),
                ]),
                "seed": .object([
                    "type": .array([.string("integer"), .string("string")]),
                    "description": .string("UInt64 seed, as an integer or a decimal string (seeds above 2^53 must be strings to survive JSON). Default: random."),
                ]),
                "mutations_per_child": .object([
                    "type": .string("number"),
                    "description": .string("Average mutations per child; each node mutates with this chance divided by the parent's node count. Default 1."),
                ]),
                "max_depth": .object([
                    "type": .string("integer"),
                    "description": .string("Deepest nesting of function calls in new random material, as for generate_genotypes. Default 10."),
                ]),
                "exclude": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Node names never introduced by a mutation (those already in the parent stay). Default none."),
                ]),
            ]),
        ])
    )

    private struct Failure: Error {
        let message: String
    }

    static func call(arguments: [String: MCP.Value]?) async -> CallTool.Result {
        do {
            return try await mutate(arguments: arguments ?? [:])
        } catch let failure as Failure {
            return errorResult(failure.message)
        } catch let failure as MCPRenderTool.Failure {
            return errorResult(failure.message)
        } catch {
            return errorResult("mutate_genotype failed: \(error.localizedDescription)")
        }
    }

    private static func mutate(arguments args: [String: MCP.Value]) async throws -> CallTool.Result {
        let (text, label) = try await MCPRenderTool.expression(from: args, tool: "mutate_genotype")
        let parent: GeneratedExpression
        do {
            parent = try GeneratedExpression(parsing: text)
        } catch {
            throw Failure(message: "Failed to read \(label): \(error)")
        }

        let seed = try seed(args["seed"])
        let count = try integer(args["count"], "count") ?? 19
        guard (1...maxCount).contains(count) else {
            throw Failure(message: "count must be 1-\(maxCount).")
        }

        var generatorConfiguration = RandomExpressionGenerator.Configuration()
        generatorConfiguration.excludedRootFunctions = UserDefaults.standard.randomExcludedRootNodes
        generatorConfiguration.excludedVariables = UserDefaults.standard.randomExcludedVariables
        if let maxDepth = try integer(args["max_depth"], "max_depth") {
            guard maxDepth >= 1 else { throw Failure(message: "max_depth must be at least 1.") }
            generatorConfiguration.maxDepth = maxDepth
        }
        if let exclude = args["exclude"] {
            guard case .array(let values) = exclude else {
                throw Failure(message: "exclude must be an array of node names.")
            }
            generatorConfiguration.excludedFunctions = Set(values.compactMap { value in
                if case .string(let name) = value { return name }
                return nil
            })
        }

        var configuration = ExpressionMutator.Configuration()
        if let rate = try number(args["mutations_per_child"], "mutations_per_child") {
            guard rate > 0 else { throw Failure(message: "mutations_per_child must be positive.") }
            configuration.mutationsPerChild = rate
        }

        let generator = RandomExpressionGenerator(signatures: NodeRegistry.shared.signatures, configuration: generatorConfiguration)
        let mutator = ExpressionMutator(generator: generator, configuration: configuration)
        let unknown = mutator.unknownNodes(in: parent)
        guard unknown.isEmpty else {
            throw Failure(message: "\(label) uses nodes that aren't loaded: \(unknown.sorted().joined(separator: ", ")).")
        }

        var rng = SeededRandomNumberGenerator(seed: seed)
        var children: [[String: Any]] = []
        for index in 0..<count {
            var child: ExpressionMutator.Child?
            for _ in 0..<maxParseRetries {
                guard let candidate = mutator.mutate(parent, using: &rng) else { break }
                // Every child is built from registered signatures, so this
                // should always parse; checked anyway so a broken one is
                // redrawn rather than returned.
                if (try? Parser().parse(candidate.expression.description)) != nil {
                    child = candidate
                    break
                }
            }
            guard let child else {
                throw Failure(message: "Couldn't make child \(index + 1): no mutation of \(label) changed it within the size limit of \(mutator.maxNodes(forParent: parent)) nodes.")
            }
            children.append([
                "expression": child.expression.description,
                "node_count": child.expression.nodeCount,
                "mutations": child.mutations.map { mutation in
                    [
                        "kind": mutation.kind.rawValue,
                        "path": mutation.path,
                        "before": mutation.before.description,
                        "after": mutation.after.description,
                    ] as [String: Any]
                },
            ])
        }

        let json: [String: Any] = [
            "seed": String(seed),
            "parent": parent.description,
            "parent_node_count": parent.nodeCount,
            "max_node_count": mutator.maxNodes(forParent: parent),
            "children": children,
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
    }

    // MARK: - Argument helpers

    private static func seed(_ value: MCP.Value?) throws -> UInt64 {
        switch value {
            case nil, .null?:
                return UInt64.random(in: 0...UInt64.max)
            case .int(let value)?:
                guard value >= 0 else { throw Failure(message: "seed must be non-negative.") }
                return UInt64(value)
            case .double(let value)?:
                guard value >= 0, value == value.rounded(), let exact = UInt64(exactly: value) else {
                    throw Failure(message: "seed must be a non-negative integer.")
                }
                return exact
            case .string(let text)?:
                guard let parsed = UInt64(text) else { throw Failure(message: "seed \"\(text)\" isn't a UInt64.") }
                return parsed
            default:
                throw Failure(message: "seed must be an integer or a decimal string.")
        }
    }

    private static func number(_ value: MCP.Value?, _ name: String) throws -> Double? {
        switch value {
            case nil, .null?: return nil
            case .int(let int)?: return Double(int)
            case .double(let double)?: return double
            default: throw Failure(message: "\(name) must be a number.")
        }
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

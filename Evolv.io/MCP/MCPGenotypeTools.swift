//
//  MCPGenotypeTools.swift
//  Evolv.io
//
//  The MCP `list_genotypes`, `write_genotype` and `delete_genotype` tools:
//  the genotype counterparts of `write_node`/`delete_node`. They read and
//  edit `.evolvgenotype` files in the user Genotypes folder (see
//  GenotypeLibrary) from inside the sandbox, then reload GenotypeStore so
//  the sidebar updates immediately. Bundled genotypes are listed but never
//  written or deleted.
//

import Foundation
import MCP
import ExpressionTree

enum MCPGenotypeTools {
    private static let nameSchema: MCP.Value = .object([
        "type": .string("string"),
        "description": .string(
            "File name, e.g. \"spiral\" or \"spiral.evolvgenotype\" -- the \".evolvgenotype\" extension is appended automatically if missing. Also the genotype's id."
        ),
    ])

    static let tools: [Tool] = [
        Tool(
            name: "list_genotypes",
            description: """
            Lists every genotype in the app's sidebar, in sidebar order, as JSON: id (file name \
            without extension), source ("bundled" or "user"), name and original_image from the \
            header when set, the expression, and the file's full contents. Also lists any load \
            issues (bad headers, empty files, ids colliding with a bundled genotype).
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "write_genotype",
            description: """
            Writes an .evolvgenotype file into Evolv.io's user-editable Genotypes folder and \
            reloads the genotype list, so it appears in the sidebar immediately. Overwrites any \
            existing user file with the same name. Content is an optional header between "---" \
            lines (name, original_image) followed by the expression. Reports load issues and \
            whether the expression parses with the current node registry.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": nameSchema,
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Full contents of the .evolvgenotype file."),
                    ]),
                ]),
                "required": .array([.string("name"), .string("content")]),
            ])
        ),
        Tool(
            name: "delete_genotype",
            description: """
            Deletes an .evolvgenotype file from Evolv.io's user-editable Genotypes folder and \
            reloads the genotype list. Bundled genotypes are never touched.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": nameSchema,
                ]),
                "required": .array([.string("name")]),
            ])
        ),
    ]

    /// Returns nil for a tool name this file doesn't handle.
    static func call(name: String, arguments: [String: MCP.Value]?) async -> CallTool.Result? {
        switch name {
        case "list_genotypes":
            return await list()
        case "write_genotype":
            guard case .string(let rawName)? = arguments?["name"],
                  case .string(let content)? = arguments?["content"] else {
                return errorResult("write_genotype requires string arguments \"name\" and \"content\".")
            }
            return await write(name: rawName, content: content)
        case "delete_genotype":
            guard case .string(let rawName)? = arguments?["name"] else {
                return errorResult("delete_genotype requires string argument \"name\".")
            }
            return await delete(name: rawName)
        default:
            return nil
        }
    }

    private struct ToolError: Error {
        let message: String
    }

    /// Resolves a tool's `name` argument to a file URL inside the user
    /// Genotypes folder, the same way `write_node` does for Nodes.
    private static func userGenotypeFileURL(for rawName: String) throws(ToolError) -> URL {
        let suffix = "." + GenotypeLibrary.fileExtension
        let fileName = rawName.hasSuffix(suffix) ? rawName : rawName + suffix
        guard !fileName.contains("/"), !fileName.contains("..") else {
            throw ToolError(message: "Invalid file name \"\(rawName)\": must be a bare file name, no path separators.")
        }
        guard let genotypesDirectory = GenotypeLibrary.containerGenotypesDirectory else {
            throw ToolError(message: "Could not resolve the container Genotypes directory.")
        }
        return genotypesDirectory.appendingPathComponent(fileName)
    }

    @MainActor
    private static func list() -> CallTool.Result {
        let store = GenotypeStore.shared
        let genotypes: [[String: Any]] = store.genotypes.map { genotype in
            var entry: [String: Any] = [
                "id": genotype.id,
                "source": genotype.source.rawValue,
                "expression": genotype.expression,
                "content": (try? String(contentsOf: genotype.fileURL, encoding: .utf8)) ?? "",
            ]
            if let name = genotype.name {
                entry["name"] = name
            }
            if let originalImageName = genotype.originalImageName {
                entry["original_image"] = originalImageName
            }
            return entry
        }
        let issues: [[String: Any]] = store.loadIssues.map {
            ["file": $0.fileURL.lastPathComponent, "message": $0.message]
        }
        let json: [String: Any] = ["genotypes": genotypes, "load_issues": issues]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
        } catch {
            return errorResult("Failed to encode genotypes: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func write(name rawName: String, content: String) -> CallTool.Result {
        let fileURL: URL
        do {
            fileURL = try userGenotypeFileURL(for: rawName)
        } catch {
            return errorResult(error.message)
        }
        let fileName = fileURL.lastPathComponent

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return errorResult("Failed to write \(fileName): \(error.localizedDescription)")
        }

        let store = GenotypeStore.shared
        store.reload()

        var problems = store.loadIssues
            .filter { $0.fileURL.lastPathComponent == fileName }
            .map(\.message)
        let id = fileURL.deletingPathExtension().lastPathComponent
        if let genotype = store.genotypes.first(where: { $0.id == id && $0.source == .user }) {
            do {
                _ = try Parser().parse(genotype.expression)
            } catch {
                problems.append("Expression doesn't parse: \(error.localizedDescription)")
            }
            if genotype.originalImageName != nil, genotype.originalImageURL == nil {
                problems.append("original_image \"\(genotype.originalImageName!)\" wasn't found beside the file or in the app bundle.")
            }
        }

        if problems.isEmpty {
            return CallTool.Result(content: [.text(
                text: "Wrote \(fileName) and reloaded the genotype list (\(store.genotypes.count) genotype(s), no issues for this file).",
                annotations: nil, _meta: nil
            )])
        }
        return errorResult("Wrote \(fileName), but found issue(s):\n\(problems.joined(separator: "\n"))")
    }

    @MainActor
    private static func delete(name rawName: String) -> CallTool.Result {
        let fileURL: URL
        do {
            fileURL = try userGenotypeFileURL(for: rawName)
        } catch {
            return errorResult(error.message)
        }
        let fileName = fileURL.lastPathComponent

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return errorResult("No file named \(fileName) in the user Genotypes folder; nothing deleted.")
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            return errorResult("Failed to delete \(fileName): \(error.localizedDescription)")
        }

        GenotypeStore.shared.reload()

        return CallTool.Result(content: [.text(
            text: "Deleted \(fileName) and reloaded the genotype list (\(GenotypeStore.shared.genotypes.count) genotype(s)).",
            annotations: nil, _meta: nil
        )])
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}

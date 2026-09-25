//
//  EvolvMCPServer.swift
//  Evolv.io
//
//  An in-process MCP server exposing Evolv.io's user-editable Nodes folder
//  to external tools (e.g. an AI coding assistant) that can't reach the
//  app's own sandboxed container over the filesystem -- the app itself has
//  no such restriction on its own container, so writes/reloads routed
//  through here sidestep the TCC wall entirely. Loopback-only; not meant
//  to be reachable from anywhere but this machine.
//

import Foundation
import Network
import MCP
import ExpressionTree

actor EvolvMCPServer {
    static let shared = EvolvMCPServer()

    private static let port = NWEndpoint.Port(rawValue: 4848)!

    private var listener: NWListener?

    func start() async {
        guard listener == nil else { return }

        let mcpServer = Server(
            name: "evolv-io",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await Self.registerHandlers(on: mcpServer)

        let transport = StatelessHTTPServerTransport()
        do {
            try await mcpServer.start(transport: transport)
        } catch {
            print("EvolvMCPServer: failed to start MCP server: \(error)")
            return
        }
        await Self.allowRepeatedInitialize(on: mcpServer)

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: Self.port)
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            print("EvolvMCPServer: failed to create listener on port \(Self.port): \(error)")
            return
        }

        listener.newConnectionHandler = { connection in
            Task { await Self.handle(connection: connection, transport: transport) }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("EvolvMCPServer: listener failed: \(error)")
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        print("EvolvMCPServer: listening on 127.0.0.1:\(Self.port)")
    }

    // MARK: - MCP tool registration

    private static func registerHandlers(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [
                Tool(
                    name: "write_node",
                    description: """
                    Writes an .evolvnode file into Evolv.io's user-editable Nodes folder \
                    and reloads the node registry, so the change renders immediately \
                    without an Xcode rebuild. Overwrites any existing file with the same name.
                    """,
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "File name, e.g. \"log\" or \"log.evolvnode\" -- the \".evolvnode\" extension is appended automatically if missing."
                                ),
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("Full contents of the .evolvnode file."),
                            ]),
                        ]),
                        "required": .array([.string("name"), .string("content")]),
                    ])
                ),
                Tool(
                    name: "delete_node",
                    description: """
                    Deletes an .evolvnode file from Evolv.io's user-editable Nodes folder \
                    and reloads the node registry. Bundled nodes are never touched.
                    """,
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object([
                                "type": .string("string"),
                                "description": .string(
                                    "File name, e.g. \"log\" or \"log.evolvnode\" -- the \".evolvnode\" extension is appended automatically if missing."
                                ),
                            ]),
                        ]),
                        "required": .array([.string("name")]),
                    ])
                ),
                MCPRenderTool.tool,
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "write_node":
                guard case .string(let rawName)? = params.arguments?["name"],
                      case .string(let content)? = params.arguments?["content"] else {
                    return errorResult("write_node requires string arguments \"name\" and \"content\".")
                }
                return writeNode(name: rawName, content: content)
            case "delete_node":
                guard case .string(let rawName)? = params.arguments?["name"] else {
                    return errorResult("delete_node requires string argument \"name\".")
                }
                return deleteNode(name: rawName)
            case "render":
                return await MCPRenderTool.call(arguments: params.arguments)
            default:
                return errorResult("Unknown tool: \(params.name)")
            }
        }
    }

    /// `Server.start(transport:)` (swift-sdk) registers a default `initialize`
    /// handler that permanently rejects a second handshake for the lifetime
    /// of the `Server` actor (`isInitialized` never resets) -- fine for a
    /// single short-lived client process, wrong here: this app, and its MCP
    /// server, outlive any one assistant session. Without this override, the
    /// first MCP client to ever connect after app launch claims the server
    /// forever, and every later client (a new coding-assistant session, a
    /// reconnect after a hiccup, ...) gets "Server is already initialized"
    /// and never gets to call any tool -- even though tool calls would have
    /// worked fine, since `isInitialized` was already permanently true.
    /// Re-registering the handler (after `start()`, so it wins the
    /// dictionary overwrite) makes `initialize` idempotent: every handshake
    /// succeeds, mirroring the default handler's success path minus the
    /// once-only guard.
    private static func allowRepeatedInitialize(on mcpServer: Server) async {
        await mcpServer.withMethodHandler(Initialize.self) { params in
            let negotiatedProtocolVersion = Version.supported.contains(params.protocolVersion)
                ? params.protocolVersion
                : Version.latest
            return Initialize.Result(
                protocolVersion: negotiatedProtocolVersion,
                capabilities: await mcpServer.capabilities,
                serverInfo: Server.Info(name: mcpServer.name, version: mcpServer.version),
                instructions: mcpServer.instructions
            )
        }
    }

    private static func errorResult(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }

    /// Resolves a tool's `name` argument to a file URL inside the user Nodes
    /// folder: appends `.evolvnode` if missing and rejects anything that could
    /// escape the folder. The thrown message is meant to be sent back as-is.
    private static func userNodeFileURL(for rawName: String) throws(ToolError) -> URL {
        let fileName = rawName.hasSuffix(".evolvnode") ? rawName : rawName + ".evolvnode"
        guard !fileName.contains("/"), !fileName.contains("..") else {
            throw ToolError(message: "Invalid file name \"\(rawName)\": must be a bare file name, no path separators.")
        }
        guard let nodesDirectory = DSLLibrary.containerNodesDirectory else {
            throw ToolError(message: "Could not resolve the container Nodes directory.")
        }
        return nodesDirectory.appendingPathComponent(fileName)
    }

    private struct ToolError: Error {
        let message: String
    }

    private static func writeNode(name rawName: String, content: String) -> CallTool.Result {
        let fileURL: URL
        do {
            fileURL = try userNodeFileURL(for: rawName)
        } catch {
            return errorResult(error.message)
        }
        let fileName = fileURL.lastPathComponent

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Failed to write \(fileName): \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        NodeRegistry.shared.reload()

        let relevantIssues = NodeRegistry.shared.loadIssues.filter { $0.fileURL.lastPathComponent == fileName }
        if relevantIssues.isEmpty {
            return CallTool.Result(content: [.text(
                text: "Wrote \(fileName) and reloaded the node registry (\(NodeRegistry.shared.registry.count) node(s) registered, no load issues for this file).",
                annotations: nil, _meta: nil
            )])
        } else {
            let messages = relevantIssues.map(\.message).joined(separator: "\n")
            return CallTool.Result(
                content: [.text(text: "Wrote \(fileName), but reload reported issue(s):\n\(messages)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func deleteNode(name rawName: String) -> CallTool.Result {
        let fileURL: URL
        do {
            fileURL = try userNodeFileURL(for: rawName)
        } catch {
            return errorResult(error.message)
        }
        let fileName = fileURL.lastPathComponent

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return errorResult("No file named \(fileName) in the user Nodes folder; nothing deleted.")
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            return errorResult("Failed to delete \(fileName): \(error.localizedDescription)")
        }

        NodeRegistry.shared.reload()

        return CallTool.Result(content: [.text(
            text: "Deleted \(fileName) and reloaded the node registry (\(NodeRegistry.shared.registry.count) node(s) registered).",
            annotations: nil, _meta: nil
        )])
    }

    // MARK: - Minimal HTTP/1.1 bridge (loopback only, one request per connection)
    //
    // StatelessHTTPServerTransport is framework-agnostic -- it only converts
    // between MCP's HTTPRequest/HTTPResponse value types and JSON-RPC, and
    // expects something else to own the actual socket. The SDK's own example
    // (MCPConformanceServer) does that with SwiftNIO; this hand-rolls the
    // same bridge with Network.framework instead, to avoid pulling in NIO as
    // a second new dependency for a single-endpoint, no-SSE, loopback-only
    // dev tool. Deliberately narrow: no chunked transfer-encoding, no
    // keep-alive/pipelining -- one request per connection, then close.

    private static func handle(connection: NWConnection, transport: StatelessHTTPServerTransport) async {
        connection.start(queue: .global(qos: .userInitiated))

        guard let requestData = await readRequest(from: connection),
              let httpRequest = parseRequest(requestData) else {
            connection.cancel()
            return
        }

        let response = await transport.handleRequest(httpRequest)
        await write(response: response, to: connection)
        connection.cancel()
    }

    private static func readRequest(from connection: NWConnection) async -> Data? {
        var buffer = Data()
        let headerTerminator = Data("\r\n\r\n".utf8)
        var headerEnd: Data.Index?
        var contentLength = 0

        // Bounded rather than infinite -- a stuck/misbehaving connection
        // drops the request instead of hanging this task forever.
        for _ in 0..<4096 {
            if headerEnd == nil, let range = buffer.range(of: headerTerminator) {
                headerEnd = range.upperBound
                contentLength = Self.contentLength(inHeaderBytes: buffer[buffer.startIndex..<range.lowerBound])
            }
            if let headerEnd, buffer.distance(from: headerEnd, to: buffer.endIndex) >= contentLength {
                return buffer
            }
            guard let chunk = await receiveChunk(from: connection) else {
                return nil
            }
            buffer.append(chunk)
        }
        return nil
    }

    private static func contentLength(inHeaderBytes headerBytes: Data) -> Int {
        guard let headerText = String(data: headerBytes, encoding: .utf8) else { return 0 }
        for line in headerText.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func receiveChunk(from connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        let headerTerminator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: headerTerminator),
              let headerText = String(data: data[data.startIndex..<range.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: true)
        guard let requestLine = lines.first else { return nil }
        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count >= 2 else { return nil }
        let method = String(requestLineParts[0])
        let path = String(requestLineParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }

        let body = data[range.upperBound...]
        return HTTPRequest(method: method, headers: headers, body: body.isEmpty ? nil : Data(body), path: path)
    }

    private static func write(response: HTTPResponse, to connection: NWConnection) async {
        let reason = reasonPhrase(for: response.statusCode)
        var raw = "HTTP/1.1 \(response.statusCode) \(reason)\r\n"

        let body = response.bodyData ?? Data()
        var headers = response.headers
        headers["Content-Length"] = "\(body.count)"
        headers["Connection"] = "close"
        for (key, value) in headers {
            raw += "\(key): \(value)\r\n"
        }
        raw += "\r\n"

        var rawData = Data(raw.utf8)
        rawData.append(body)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: rawData, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}

//
//  HTTPServer.swift
//  EvolvScorer
//
//  A minimal HTTP/1.1 server on Network.framework: one request per
//  connection, then close. Enough for GET /health and POST /score.
//

import Foundation
import Network

final class HTTPServer: @unchecked Sendable {
    static let version = "1.0"
    static let maxBodyBytes = 64 * 1024 * 1024

    let port: UInt16
    let lan: Bool
    let scorer: Scorer
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "EvolvScorer.http", attributes: .concurrent)

    init(port: UInt16, lan: Bool, scorer: Scorer) {
        self.port = port
        self.lan = lan
        self.scorer = scorer
    }

    func start() throws {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        if lan {
            listener = try NWListener(using: parameters, on: nwPort)
            listener.service = NWListener.Service(type: "_evolvscore._tcp")
        } else {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
            listener = try NWListener(using: parameters)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [port, lan] state in
            switch state {
            case .ready:
                let host = lan ? "all interfaces (Bonjour _evolvscore._tcp)" : "127.0.0.1"
                print("EvolvScorer: listening on \(host), port \(port)")
            case .failed(let error):
                print("EvolvScorer: listener failed: \(error)")
                exit(1)
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Reading a request

    private struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil {
                connection.cancel()
                return
            }
            switch Self.parse(buffer) {
            case .incomplete where !isComplete:
                self.receive(on: connection, buffer: buffer)
            case .incomplete:
                connection.cancel()
            case .tooLarge:
                self.send(status: 413, json: ["error": "body larger than \(Self.maxBodyBytes) bytes"], on: connection)
            case .malformed:
                self.send(status: 400, json: ["error": "malformed HTTP request"], on: connection)
            case .complete(let request):
                Task { await self.handle(request, on: connection) }
            }
        }
    }

    private enum ParseResult {
        case incomplete, malformed, tooLarge
        case complete(Request)
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > 64 * 1024 ? .malformed : .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .malformed
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length <= maxBodyBytes else { return .tooLarge }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return .incomplete }

        let components = URLComponents(string: String(requestLine[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .complete(Request(
            method: String(requestLine[0]).uppercased(),
            path: components?.path ?? "/",
            query: query,
            headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + length)])))
    }

    // MARK: - Routes

    private func handle(_ request: Request, on connection: NWConnection) async {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            send(status: 200, json: ["status": "ok", "version": Self.version, "vision": scorer.useVision], on: connection)
        case ("POST", "/score"):
            guard !request.body.isEmpty else {
                send(status: 400, json: ["error": "POST the image bytes as the body"], on: connection)
                return
            }
            do {
                let wantsFeaturePrint = ["1", "true", "yes"].contains(request.query["featurePrint"] ?? "")
                let result = try await scorer.score(request.body, id: request.query["id"], featurePrint: wantsFeaturePrint)
                send(status: 200, body: try JSONEncoder.scorer.encode(result), on: connection)
            } catch {
                send(status: 422, json: ["error": "\(error)"], on: connection)
            }
        case (_, "/health"), (_, "/score"):
            send(status: 405, json: ["error": "method not allowed"], on: connection)
        default:
            send(status: 404, json: ["error": "not found"], on: connection)
        }
    }

    // MARK: - Writing a response

    private func send(status: Int, json: [String: Any], on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        send(status: status, body: body, on: connection)
    }

    private func send(status: Int, body: Data, on connection: NWConnection) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var response = Data("""
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

extension JSONEncoder {
    static var scorer: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

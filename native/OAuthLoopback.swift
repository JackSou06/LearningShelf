import Foundation
import Network

/// An OAuth callback bound exclusively to IPv4 loopback; never exposed through course sharing.
@MainActor final class OAuthLoopback {
    private let listener: NWListener
    private let state: String
    private var startup: CheckedContinuation<URL, Error>?
    private var waiting: CheckedContinuation<[String: String], Error>?
    private var outcome: Result<[String: String], Error>?
    private var timeout: DispatchWorkItem?
    private var connections: [UUID: NWConnection] = [:]
    private(set) var redirect: URL?

    init(state: String) throws {
        self.state = state
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                guard let self else { return }
                switch status {
                case .ready:
                    guard let port = self.listener.port, self.startup != nil else { return }
                    let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
                    self.redirect = url; self.startup?.resume(returning: url); self.startup = nil
                case .failed: self.finish(.failure(CourseFailure(message: "無法啟動 ChatGPT 登入回傳，請重試")))
                default: break
                }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                guard let self, self.outcome == nil, self.connections.count < 8 else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection
                connection.start(queue: .main)
                connection.stateUpdateHandler = { [weak self] status in
                    Task { @MainActor in if case .cancelled = status { self?.connections.removeValue(forKey: id) } }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak connection] in connection?.cancel() }
                self.receive(connection, bytes: Data())
                }
            }
            let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(CourseFailure(message: "ChatGPT 登入逾時，請重試"))) }
            timeout = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: deadline)
            listener.start(queue: .main)
        }
    }
    func result() async throws -> [String: String] {
        if let outcome { return try outcome.get() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func cancel() {
        finish(.failure(CancellationError()))
        connections.values.forEach { $0.cancel() }; connections.removeAll()
    }
    private func finish(_ result: Result<[String: String], Error>) {
        guard outcome == nil else { return }
        outcome = result; timeout?.cancel(); timeout = nil; listener.cancel()
        if let startup { startup.resume(throwing: CourseFailure(message: "登入已停止")); self.startup = nil }
        waiting?.resume(with: result); waiting = nil
    }
    static func callback(target: String, expectedState: String) throws -> [String: String] {
        guard target.hasPrefix("/auth/callback?"), let parts = URLComponents(string: "http://127.0.0.1" + target), parts.path == "/auth/callback", parts.fragment == nil else {
            throw CourseFailure(message: "登入回傳路徑不符")
        }
        var values: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard values[item.name] == nil, let value = item.value else { throw CourseFailure(message: "登入回傳格式不符") }
            values[item.name] = value
        }
        guard values["state"] == expectedState else { throw CourseFailure(message: "登入回傳驗證不符") }
        return values
    }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
            guard let self else { connection.cancel(); return }
            var bytes = bytes; if let data { bytes.append(data) }
            guard error == nil, bytes.count <= 16384 else { connection.cancel(); return }
            guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if complete { connection.cancel() } else { self.receive(connection, bytes: bytes) }; return
            }
            let lines = String(decoding: bytes[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let request = lines[0].components(separatedBy: " ")
            let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            var valid = false
            if request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1", hosts == [self.redirect?.host.map { $0 + ":" + String(self.redirect!.port!) } ?? ""], self.outcome == nil,
               let values = try? Self.callback(target: request[1], expectedState: self.state) {
                valid = true
                self.finish(.success(values))
            }
            let body = valid ? "登入回傳已收到。請回到 LearningShelf 查看結果。" : "無效的登入回傳。請從 LearningShelf 重新登入。"
            let html = Data(("<!doctype html><meta charset=utf-8><title>LearningShelf</title><p>" + body + "</p>").utf8)
            let header = "HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + html, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}

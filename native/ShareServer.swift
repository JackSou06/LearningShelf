import Foundation
import Network
import Darwin

/// A scoped projection of one computer-owned course/session over the local network.
final class ShareServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LearningShelf.share")
    private let routes: [String: (Data, String)]
    private let token = UUID().uuidString.lowercased()
    private let course: LoadedCourse
    private let session: HostSession
    private var connections: [UUID: NWConnection] = [:]
    private var callback: ((Result<String, Error>) -> Void)?
    @MainActor init(webRoot: URL, course: LoadedCourse, session: HostSession) throws {
        self.course = course; self.session = session
        listener = try NWListener(using: .tcp, on: .any)
        var r: [String: (Data, String)] = [:]
        for f in try FileManager.default.contentsOfDirectory(at: webRoot, includingPropertiesForKeys: nil) where ["js", "css", "html"].contains(f.pathExtension) {
            r[f.lastPathComponent] = (try Data(contentsOf: f), ["js": "text/javascript", "css": "text/css", "html": "text/html"][f.pathExtension]!)
        }
        // Teaching/assets only in static files. Records use scoped endpoints; keys never leave the host.
        var pack = course.pack
        let original = pack["files"] as? [String: String] ?? [:]
        let sources = Set((course.model["sources"] as? [[String: Any]] ?? []).compactMap { $0["file"] as? String })
        pack["files"] = original.filter { !sources.contains($0.key) }; pack["base"] = ""
        let data = try JSONSerialization.data(withJSONObject: [pack])
        let authoring = (try? String(contentsOf: webRoot.deletingLastPathComponent().appendingPathComponent("Protocol/AUTHORING.md"), encoding: .utf8)) ?? (try? String(contentsOf: webRoot.deletingLastPathComponent().appendingPathComponent("protocol/AUTHORING.md"), encoding: .utf8)) ?? ""
        let authorJSON = try JSONSerialization.data(withJSONObject: [authoring])
        let hosted = try JSONSerialization.data(withJSONObject: ["courseId": course.id])
        let script = "window.HOSTED_SESSION=" + String(data: hosted, encoding: .utf8)! + ";\nwindow.BUNDLED_COURSES=" + String(data: data, encoding: .utf8)! + ";\nwindow.AUTHORING=" + String(data: authorJSON, encoding: .utf8)! + "[0];\n"
        r["library.js"] = (Data(script.utf8), "text/javascript")
        if let fonts = try? FileManager.default.contentsOfDirectory(at: webRoot.appendingPathComponent("fonts"), includingPropertiesForKeys: nil) {
            for f in fonts { r["fonts/" + f.lastPathComponent] = (try Data(contentsOf: f), "font/woff2") }
        }
        routes = r
    }
    func start(completion: @escaping (Result<String, Error>) -> Void) {
        callback = completion
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: if let port = self.listener.port { self.callback?(.success("http://\(Self.address()):\(port.rawValue)/\(self.token)/")); self.callback = nil }
            case .failed(let error): self.callback?(.failure(error)); self.callback = nil
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 32 else { connection.cancel(); return }
            let id = UUID(); self.connections[id] = connection; connection.start(queue: self.queue)
            connection.stateUpdateHandler = { [weak self] state in if case .cancelled = state { self?.connections.removeValue(forKey: id) } }
            self.queue.asyncAfter(deadline: .now() + 15) { [weak connection] in connection?.cancel() }
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }
    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { c.cancel(); return }
            var b = buffer; if let data { b.append(data) }
            guard error == nil, b.count <= 10_016_384 else { self.respond(c, code: 413); return }
            guard let range = b.range(of: Data("\r\n\r\n".utf8)) else {
                if b.count > 16384 { self.respond(c, code: 431) } else if complete { c.cancel() } else { self.receive(c, buffer: b) }; return
            }
            guard range.lowerBound <= 16384, let header = String(data: b[..<range.lowerBound], encoding: .utf8) else { self.respond(c, code: 400); return }
            let lines = header.components(separatedBy: "\r\n"), first = lines[0].components(separatedBy: " ")
            guard first.count == 3, first[2] == "HTTP/1.1", ["GET", "POST"].contains(first[0]) else { self.respond(c, code: 405); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { self.respond(c, code: 400); return }
                let name = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard headers[name] == nil else { self.respond(c, code: 400); return }; headers[name] = value
            }
            guard headers["transfer-encoding"] == nil else { self.respond(c, code: 400); return }
            let count = Int(headers["content-length"] ?? "0") ?? -1
            guard count >= 0, count <= 10_000_000 else { self.respond(c, code: 413); return }
            if first[0] == "POST", headers["content-length"] == nil { self.respond(c, code: 411); return }
            let total = range.upperBound + count
            guard b.count >= total else { if complete { c.cancel() } else { self.receive(c, buffer: b) }; return }
            let path = first[1].components(separatedBy: "?")[0], prefix = "/" + self.token + "/"
            guard path.hasPrefix(prefix) else { self.respond(c, code: 404); return }
            if let origin = headers["origin"], origin != "http://" + (headers["host"] ?? "") { self.respond(c, code: 403); return }
            if headers["sec-fetch-site"] == "cross-site" { self.respond(c, code: 403); return }
            let key = String(path.dropFirst(prefix.count))
            if key.hasPrefix("api/") {
                var payload: [String: Any] = [:]
                if first[0] == "POST" {
                    guard headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                          let json = try? JSONSerialization.jsonObject(with: Data(b[range.upperBound..<total])) as? [String: Any] else { self.respond(c, code: 400); return }
                    payload = json
                }
                Task { @MainActor [weak self] in self?.api(c, method: first[0], route: key, payload: payload) }
            } else if first[0] == "GET", let (body, mime) = self.routes[key.isEmpty ? "index.html" : key] { self.respond(c, code: 200, body: body, mime: mime) }
            else { self.respond(c, code: 404) }
        }
    }
    @MainActor private func api(_ c: NWConnection, method: String, route: String, payload: [String: Any]) {
        do {
            var value: Any
            switch (method, route) {
            case ("GET", "api/session"): value = ["courseId": course.id, "hasKey": session.hasKey, "ready": session.aiReady, "provider": session.aiConnection?.configuration.provider ?? "api", "model": session.aiConnection?.usesChatGPT == true ? session.aiConnection!.configuration.chatGPTModel : ""]
            case ("GET", "api/records"): value = try session.load(course)
            case ("POST", "api/records"):
                guard let record = payload["record"] as? [String: Any], let base = payload["base"] as? [String: Any] else { throw CourseFailure(message: "紀錄同步格式錯誤") }
                value = try session.save(record, base: base, course: course)
            case ("POST", "api/ask"):
                guard let topic = payload["topicId"] as? String, let question = payload["question"] as? String, let id = payload["requestId"] as? String else { throw CourseFailure(message: "問題格式錯誤") }
                value = try session.ask(course, topicId: topic, question: question, requestId: id)
            case ("POST", "api/cancel"):
                guard let id = payload["requestId"] as? String else { throw CourseFailure(message: "問題格式錯誤") }; value = try session.cancel(course, requestId: id)
            case ("POST", "api/markdown"): value = ["status": try session.syncMarkdown(course)]
            default: respond(c, code: 404); return
            }
            respond(c, code: 200, body: try JSONSerialization.data(withJSONObject: value), mime: "application/json")
        } catch { let body = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data(); respond(c, code: 400, body: body, mime: "application/json") }
    }
    private func respond(_ c: NWConnection, code: Int, body: Data = Data(), mime: String = "text/plain") {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 411: "Length Required", 413: "Payload Too Large", 431: "Request Header Fields Too Large"][code] ?? "Error"
        var bytes = Data("HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(mime); charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8)
        bytes.append(body); c.send(content: bytes, completion: .contentProcessed { _ in c.cancel() })
    }
    func stop() { listener.cancel(); queue.async { [weak self] in guard let self else { return }; for c in self.connections.values { c.cancel() }; self.connections.removeAll() } }
    deinit { listener.cancel(); for c in connections.values { c.cancel() } }
    static func address() -> String {
        var list: UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&list) == 0 else { return "127.0.0.1" }; defer { freeifaddrs(list) }
        var p = list, result = "127.0.0.1"
        while let node = p {
            let a = node.pointee
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: a.ifa_name).hasPrefix("en") {
                var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 { result = String(cString: name); if String(cString: a.ifa_name) == "en0" { break } }
            }
            p = a.ifa_next
        }
        return result
    }
}

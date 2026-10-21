import Foundation
import Security
import Network

@MainActor final class OAuthFixture {
    let privateKey: SecKey
    let jwks: [String: Any]
    var nonce = "", challenge = "", hostID = "", redirect = ""
    var client = "oaiapp_fixture_one", callbackClient: String?
    var subject = "subject-one", scope = "openid email profile offline_access resource.invoke chatgpt.tokens.use.direct"
    var invalidSignature = false, refreshCount = 0, firstExpiry: Double = 3600
    var exchanges = 0, opens = 0, revocations = 0
    var lastForm: [String: String] = [:]
    init() throws {
        privateKey = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let data = SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(privateKey)!, nil)! as Data
        // Read the PKCS#1 public modulus and exponent for the test-only JWKS.
        var offset = 0
        func element() -> Data {
            offset += 1; var size = Int(data[offset]); offset += 1
            if size & 128 != 0 { let n = size & 127; size = 0; for _ in 0..<n { size = (size << 8) | Int(data[offset]); offset += 1 } }
            let value = data[offset..<offset+size]; offset += size; return Data(value)
        }
        _ = element(); offset = data.count > 255 ? 4 : 3
        var n = element(); if n.first == 0 { n.removeFirst() }; let e = element()
        jwks = ["keys": [["kty": "RSA", "kid": "fixture-key", "alg": "RS256", "use": "sig", "n": OpenAIIdentity.base64URL(n), "e": OpenAIIdentity.base64URL(e)]]]
    }
    func token(client: String, nonce: String?, issuer: String = "https://auth.openai.com", expiry: Double = Date().addingTimeInterval(3600).timeIntervalSince1970) throws -> String {
        let header = OpenAIIdentity.base64URL(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "fixture-key"]))
        var claims: [String: Any] = ["iss": issuer, "sub": subject, "aud": client, "exp": expiry, "email": "fixture@example.invalid"]
        if let nonce { claims["nonce"] = nonce }
        let payload = OpenAIIdentity.base64URL(try JSONSerialization.data(withJSONObject: claims))
        let text = header + "." + payload
        let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(text.utf8) as CFData, nil)! as Data
        return text + "." + OpenAIIdentity.base64URL(invalidSignature ? Data(repeating: 0, count: signature.count) : signature)
    }
    func browser(_ url: URL) -> Bool {
        opens += 1
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let p = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        nonce = p["nonce"]!; challenge = p["code_challenge"]!; hostID = p["ext_agent_host_id"]!; redirect = p["redirect_uri"]!
        precondition(url.host == "auth.openai.com" && p["resource"] == AIConnection.resource && p["scope"]!.contains("chatgpt.tokens.use.direct"))
        precondition(p["client_id"] == "dynamic_agent_client" ? p["agent_name_hint"] == "LearningShelf" : p["agent_name_hint"] == nil)
        var callback = URLComponents(string: redirect)!
        callback.queryItems = [URLQueryItem(name: "state", value: p["state"]!), URLQueryItem(name: "code", value: "fixture-code"), URLQueryItem(name: "client_id", value: callbackClient ?? client)]
        Task { _ = try? await URLSession.shared.data(from: callback.url!) }
        return true
    }
    func http(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        var body: [String: Any]
        if path == "/.well-known/openid-configuration" {
            body = ["issuer": AIConnection.issuer, "authorization_endpoint": AIConnection.issuer + "/api/accounts/authorize", "token_endpoint": AIConnection.issuer + "/api/accounts/oauth/token", "jwks_uri": AIConnection.issuer + "/.well-known/jwks.json", "revocation_endpoint": AIConnection.issuer + "/api/accounts/oauth/revoke"]
        } else if path == "/.well-known/jwks.json" { body = jwks }
        else if path == "/api/accounts/oauth/revoke" { revocations += 1; return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        else if path == "/v1/models" {
            precondition(request.value(forHTTPHeaderField: "Authorization")!.hasPrefix("Bearer fixture-access"))
            body = ["models": [["slug": "fixture-hidden", "display_name": "Hidden", "visibility": "hide"], ["slug": "fixture-model", "display_name": "Fixture model", "visibility": "list"]]]
        } else {
            precondition(path == "/api/accounts/oauth/token")
            let form = String(data: request.httpBody!, encoding: .utf8)!
            let parts = URLComponents(string: "http://fixture/?" + form)!.queryItems!
            lastForm = Dictionary(uniqueKeysWithValues: parts.map { ($0.name, $0.value ?? "") })
            precondition(lastForm["resource"] == AIConnection.resource)
            if lastForm["grant_type"] == "authorization_code" {
                exchanges += 1
                precondition(OpenAIIdentity.challenge(lastForm["code_verifier"]!) == challenge && lastForm["redirect_uri"] == redirect)
                body = ["id_token": try token(client: lastForm["client_id"]!, nonce: nonce), "expires_in": firstExpiry]
            } else {
                refreshCount += 1; try await Task.sleep(nanoseconds: 50_000_000)
                precondition(lastForm["scope"] == nil && lastForm["client_id"] != "dynamic_agent_client")
                body = ["expires_in": 3600]
            }
            body["access_token"] = "fixture-access-\(refreshCount)"; body["refresh_token"] = "fixture-refresh-\(refreshCount)"
            body["scope"] = scope; body["token_type"] = "Bearer"
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@main struct AIConnectionChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("LearningShelf-ai-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "", line: UInt = #line) throws { if try !condition() { fatalError("Check failed at \(line): \(message)") } }
        func rejected(_ body: () throws -> Void) throws { do { try body(); fatalError("Expected rejection") } catch {} }
        var migrations = 0
        let fixture = try OAuthFixture(), directory = temp.appendingPathComponent("Credentials")
        var sent: [URLRequest] = [], apiCalls = 0, delay = false, quota = false
        let ai = AIConnection(directory: directory, legacyKey: { migrations += 1; return "fixture-legacy-key" }, http: fixture.http, streamer: { request in
            sent.append(request)
            if delay { try await Task.sleep(nanoseconds: 2_000_000_000) }
            if quota { throw CourseFailure(message: "ChatGPT 方案額度已達上限") }
            return ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "fixture answer"]]]], "usage": ["input_tokens": 300, "output_tokens": 20]]
        })
        try check(ai.apiKey() == "fixture-legacy-key" && ai.apiKey() == "fixture-legacy-key" && migrations == 1)
        try check((fm.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try check((fm.attributesOfItem(atPath: directory.appendingPathComponent("api-key").path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let loader = try CourseLoader(webRoot: root.appendingPathComponent("web")), original = try loader.load(root.appendingPathComponent("courses/linear-algebra"))
        var model = original.model, topics = model["topics"] as! [[String: Any]], blocks = topics[0]["blocks"] as! [[String: Any]]
        blocks.append(["id": "private-detail", "type": "markdown", "visibility": "contextOnly", "text": "HIDDEN_DETAIL_SENTINEL"]); topics[0]["blocks"] = blocks; model["topics"] = topics
        let course = LoadedCourse(root: original.root, pack: original.pack, model: model)
        let records = try RecordStore(folder: temp.appendingPathComponent("records"))
        let host = try HostSession(webRoot: root.appendingPathComponent("web"), records: records, transport: { _, completion in
            apiCalls += 1; completion(.success(["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "API answer"]]]]])); return {}
        }, aiConnection: ai)
        try host.setKey("", remember: false); try check(ai.apiKey() == "fixture-legacy-key")
        try host.setKey("fixture-temporary", remember: false); try check(host.activeKey == "fixture-temporary" && ai.apiKey() == "fixture-legacy-key")
        try host.setKey("fixture-saved", remember: true); try check(host.temporaryKey.isEmpty && host.activeKey == "fixture-saved")
        let reopened = AIConnection(directory: directory); try check(reopened.apiKey() == "fixture-saved", "replacement app reuses stable external credential files")
        try await ai.login(openBrowser: fixture.browser)
        try check(ai.selected?.subject == "subject-one" && ai.selected?.enabled == true && fixture.exchanges == 1)
        let hostID = ai.configuration.hostID
        try check(hostID == fixture.hostID && reopened.configuration.hostID != hostID)
        try await ai.models(); try check(ai.modelCatalog.count == 1 && ai.configuration.chatGPTModel == "fixture-model")
        try ai.setProvider("chatgpt")
        var state = try host.load(course); state["notes"] = ["vector": "CURRENT_TOPIC_NOTE", "linear-combination": "OTHER_TOPIC_NOTE"]
        state["qa"] = [["id": "old", "topic": "vector", "question": "OLD_QUESTION", "answer": "OLD_ANSWER", "status": "done", "time": "2026-10-21T00:00:00Z", "version": course.version, "model": "fixture-model", "error": ""]]
        _ = try host.save(state, base: try host.load(course), course: course)
        _ = try host.ask(course, topicId: "vector", question: "NEW_QUESTION", requestId: "chatgpt-question")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(sent.count == 1 && apiCalls == 0)
        let request = sent[0], body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        try check(body["stream"] as? Bool == true && body["store"] as? Bool == false && body["model"] as? String == "fixture-model")
        let text = String(data: request.httpBody!, encoding: .utf8)!
        for expected in ["HIDDEN_DETAIL_SENTINEL", "CURRENT_TOPIC_NOTE", "OLD_QUESTION", "OLD_ANSWER", "NEW_QUESTION"] { try check(text.contains(expected)) }
        try check(!text.contains("OTHER_TOPIC_NOTE") && !text.contains("fixture-access") && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-0")
        try check((try host.load(course)["qa"] as! [[String: Any]]).last?["status"] as? String == "done")
        let status = String(data: try JSONSerialization.data(withJSONObject: host.connectionInfo()), encoding: .utf8)!
        try check(!status.contains("fixture-access") && !status.contains("fixture-saved") && !status.contains("fixture-refresh"))
        quota = true; _ = try host.ask(course, topicId: "vector", question: "quota", requestId: "quota-question")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(apiCalls == 0 && (try host.load(course)["qa"] as! [[String: Any]]).last?["status"] as? String == "error")
        quota = false; delay = true; _ = try host.ask(course, topicId: "vector", question: "cancel", requestId: "cancel-question")
        _ = try host.cancel(course, requestId: "cancel-question"); try await Task.sleep(nanoseconds: 100_000_000)
        try check((try host.load(course)["qa"] as! [[String: Any]]).last?["status"] as? String == "cancelled")
        delay = false; try ai.setProvider("api")
        _ = try host.ask(course, topicId: "vector", question: "API mode", requestId: "api-question"); try await Task.sleep(nanoseconds: 100_000_000)
        try check(apiCalls == 1)
        let retainedID = ai.selected!.clientID
        fixture.callbackClient = "oaiapp_wrong"
        do { try await ai.login(profileID: retainedID, openBrowser: fixture.browser); fatalError("client mismatch accepted") } catch {}
        try check(ai.selected?.clientID == retainedID && ai.selected?.enabled == true)
        fixture.callbackClient = nil; fixture.invalidSignature = true; fixture.client = "oaiapp_bad_signature"
        do { try await ai.login(openBrowser: fixture.browser); fatalError("bad signature accepted") } catch {}
        try check(ai.selected?.clientID == retainedID)
        fixture.invalidSignature = false; fixture.client = "oaiapp_identity_only"; fixture.scope = "openid email profile"
        try await ai.login(openBrowser: fixture.browser); try check(ai.selected?.enabled == false)
        try ai.setProvider("chatgpt")
        try rejected { _ = try host.ask(course, topicId: "vector", question: "not authorized", requestId: "forbidden") }
        try ai.selectProfile(retainedID); try await ai.models()
        fixture.client = retainedID; fixture.scope = "openid email profile offline_access resource.invoke chatgpt.tokens.use.direct"; fixture.firstExpiry = 1
        try await ai.login(profileID: retainedID, openBrowser: fixture.browser)
        async let first = ai.authorizedProfile(retainedID); async let second = ai.authorizedProfile(retainedID)
        let (a, b) = try await (first, second)
        try check(a.accessToken == b.accessToken && fixture.refreshCount == 1 && ai.selected?.refreshToken == "fixture-refresh-1")
        let restart = AIConnection(directory: directory); try check(restart.configuration.hostID == hostID && restart.selected?.refreshToken == "fixture-refresh-1")
        try await ai.logout(); try check(ai.selected?.accessToken == "" && ai.selected?.refreshToken == "" && fixture.revocations == 1 && ai.hasKey)
        try host.forgetKey(); try check(ai.apiKey() == nil && migrations == 1)
        let lease = try AIRefreshLease(directory: directory); try rejected { _ = try AIRefreshLease(directory: directory) }; lease.release()
        // Signed ID-token identity checks are independent of the OAuth happy path.
        let valid = try fixture.token(client: retainedID, nonce: "expected")
        _ = try OpenAIIdentity.verify(valid, jwks: fixture.jwks, clientID: retainedID, nonce: "expected")
        try rejected { _ = try OpenAIIdentity.verify(valid, jwks: fixture.jwks, clientID: "other", nonce: "expected") }
        try rejected { _ = try OpenAIIdentity.verify(valid, jwks: fixture.jwks, clientID: retainedID, nonce: "wrong") }
        try rejected { _ = try OpenAIIdentity.verify(fixture.token(client: retainedID, nonce: "expected", issuer: "https://untrusted.invalid"), jwks: fixture.jwks, clientID: retainedID, nonce: "expected") }
        try rejected { _ = try OpenAIIdentity.verify(fixture.token(client: retainedID, nonce: "expected", expiry: 0), jwks: fixture.jwks, clientID: retainedID, nonce: "expected") }
        try rejected { _ = try OAuthLoopback.callback(target: "/auth/callback?state=wrong&code=x", expectedState: "right") }
        try rejected { _ = try OAuthLoopback.callback(target: "/auth/callback?state=right&state=right", expectedState: "right") }
        try rejected { _ = try OAuthLoopback.callback(target: "/callback?state=right", expectedState: "right") }
        var stream = ResponsesStream()
        _ = try stream.line("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}"); try check(try stream.line("") == nil)
        _ = try stream.line("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}")
        try check(try stream.line("")?["status"] as? String == "completed")
        for terminal in ["response.failed", "response.incomplete", "error"] {
            var failed = ResponsesStream(); _ = try failed.line("data: {\"type\":\"\(terminal)\",\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}")
            try rejected { _ = try failed.line("") }
        }
        // Exercise Foundation's real byte/line stream, not only the parser or mocked host transport.
        func networkStream(_ payload: String) async throws -> [String: Any] {
            let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                    let body = Data(payload.utf8)
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { status in
                    if case .ready = status { continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/stream")!) }
                    if case .failed(let error) = status { continuation.resume(throwing: error) }
                }
                listener.start(queue: .main)
            }
            defer { listener.cancel() }
            var request = URLRequest(url: url); request.timeoutInterval = 5
            return try await AIConnection.stream(request)
        }
        let finalEvent = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"模擬文字\"}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\n\n"
        let networkResult = try await networkStream(finalEvent); try check(networkResult["status"] as? String == "completed")
        do { _ = try await networkStream("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"); fatalError("interrupted stream accepted") } catch {}
        let interrupted = AIConnection(directory: temp.appendingPathComponent("cancelled"), http: fixture.http)
        var opened = false
        let login = Task { try await interrupted.login(openBrowser: { _ in opened = true; return true }) }
        while !opened { try await Task.sleep(nanoseconds: 10_000_000) }
        interrupted.cancelLogin(); do { try await login.value; fatalError("cancel accepted") } catch {}
        try check(!interrupted.loggingIn && interrupted.selected == nil)
        let damagedFiles = AICredentialFiles(directory: temp.appendingPathComponent("damaged"))
        try damagedFiles.write(Data("broken JSON".utf8), name: "connection.json")
        try damagedFiles.write(Data("fixture-key-must-not-be-used".utf8), name: "api-key")
        let damaged = AIConnection(directory: damagedFiles.directory)
        try check(!damaged.ready)
        try rejected { try damaged.validate() }
        try rejected { try damaged.setProvider("api") }
        try check(try damagedFiles.read("connection.json") == Data("broken JSON".utf8))
        print("AI connection checks passed: protected persistence and legacy migration; real loopback OAuth with PKCE/state/nonce/JWKS; account isolation and scopes; model catalog; serialized rotating refresh; revocation; identical hidden topic context; explicit providers; no API fallback; cancellation; terminal SSE errors and completion.")
    }
}

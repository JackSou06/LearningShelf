import Foundation
import AppKit

struct ChatGPTProfile: Codable {
    let clientID: String
    var subject = ""
    var email = ""
    var accessToken = ""
    var refreshToken = ""
    var idToken = ""
    var scopes: [String] = []
    var expiresAt = Date.distantPast
    var enabled: Bool { !accessToken.isEmpty && scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke") }
    var label: String { (email.isEmpty ? "ChatGPT 帳號" : email) + " · " + String(clientID.suffix(8)) }
}

struct AIConfiguration: Codable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var provider = "api"
    var selectedProfileID = ""
    var chatGPTModel = ""
    var profiles: [ChatGPTProfile] = []
}

/// Authentication stays in the native host. Neither WKWebView nor the shared reader receives tokens.
@MainActor final class AIConnection {
    typealias HTTP = (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias Stream = (URLRequest) async throws -> [String: Any]
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    let files: AICredentialFiles
    private(set) var configuration = AIConfiguration()
    private(set) var notice = ""
    private var storageError: Error?
    private let http: HTTP
    private let streamer: Stream
    private let legacyKey: () throws -> String?
    private let legacyClear: () throws -> Void
    private var callback: OAuthLoopback?
    private var attempt: UUID?
    private var refreshes: [String: Task<ChatGPTProfile, Error>] = [:]
    private(set) var modelCatalog: [[String: String]] = []
    var selected: ChatGPTProfile? { configuration.profiles.first { $0.clientID == configuration.selectedProfileID } }
    var usesChatGPT: Bool { configuration.provider == "chatgpt" }
    var hasKey: Bool { (try? apiKey())?.isEmpty == false }
    var ready: Bool { storageError == nil && (usesChatGPT ? selected?.enabled == true : hasKey) }
    var loggingIn: Bool { attempt != nil }

    init(directory: URL, legacyKey: @escaping () throws -> String? = { nil }, legacyClear: @escaping () throws -> Void = {}, http: @escaping HTTP = AIConnection.request, streamer: @escaping Stream = AIConnection.stream) {
        files = AICredentialFiles(directory: directory); self.legacyKey = legacyKey; self.legacyClear = legacyClear; self.http = http; self.streamer = streamer
        do {
            if let bytes = try files.read("connection.json") {
                let saved = try JSONDecoder().decode(AIConfiguration.self, from: bytes)
                guard ["api", "chatgpt"].contains(saved.provider) else { throw CourseFailure(message: "AI 連線方式無效") }
                configuration = saved
            }
        } catch { storageError = error; notice = "AI 設定無法讀取；原檔已保留，請檢查此 Mac 的檔案權限。" }
    }
    func validate() throws { if storageError != nil { throw CourseFailure(message: notice) } }
    private func save(_ next: AIConfiguration) throws {
        guard storageError == nil else { throw CourseFailure(message: notice) }
        try files.write(JSONEncoder().encode(next), name: "connection.json"); configuration = next
    }
    func apiKey() throws -> String? {
        if let data = try files.read("api-key") { return String(data: data, encoding: .utf8) }
        // A tombstone prevents an explicitly removed key from being imported again from old versions.
        guard try files.read("legacy-key-handled") == nil else { return nil }
        if let key = try legacyKey(), !key.isEmpty {
            try saveKey(key); notice = "已沿用舊版金鑰，之後更新 App 會保留。"; return key
        }
        return nil
    }
    func saveKey(_ key: String) throws {
        guard !key.isEmpty else { return }
        try files.write(Data(key.utf8), name: "api-key")
        try files.write(Data("1".utf8), name: "legacy-key-handled")
    }
    func forgetKey() throws {
        // Write the marker first, so a failure cannot resurrect an explicitly removed legacy key.
        try files.write(Data("1".utf8), name: "legacy-key-handled"); try files.remove("api-key")
        do { try legacyClear(); notice = "已清除 API Key；ChatGPT 帳號設定仍保留。" }
        catch { notice = "新設定中的 API Key 已清除，但舊 Keychain 項目未能刪除；請在「鑰匙圈存取」中清除 LearningShelf 舊金鑰。" }
    }
    func setProvider(_ value: String) throws {
        guard ["api", "chatgpt"].contains(value) else { throw CourseFailure(message: "AI 連線方式無效") }
        var next = configuration; next.provider = value; try save(next)
    }
    func selectProfile(_ id: String) throws {
        guard configuration.profiles.contains(where: { $0.clientID == id }) else { throw CourseFailure(message: "請選擇已保存的帳號") }
        guard !loggingIn else { throw CourseFailure(message: "請先完成或取消目前的登入") }
        var next = configuration; next.selectedProfileID = id; next.chatGPTModel = ""; try save(next); modelCatalog = []
    }
    func selectModel(_ model: String) throws {
        guard modelCatalog.contains(where: { $0["slug"] == model }) else { throw CourseFailure(message: "請從此帳號可用的模型中選擇") }
        var next = configuration; next.chatGPTModel = model; try save(next)
    }
    func info() -> [String: Any] {
        var message = notice
        let remembered: Bool
        do { remembered = (try apiKey())?.isEmpty == false }
        catch { remembered = false; message = "已保存的金鑰目前無法讀取，請檢查檔案權限或 Keychain 授權；原資料沒有清除。" }
        return ["provider": configuration.provider, "hasKey": remembered, "remembered": remembered,
                "ready": storageError == nil && (usesChatGPT ? selected?.enabled == true : remembered), "loggingIn": loggingIn,
                "selectedProfileID": configuration.selectedProfileID, "chatGPTModel": configuration.chatGPTModel,
                "profiles": configuration.profiles.map { ["id": $0.clientID, "label": $0.label, "enabled": $0.enabled, "connected": !$0.accessToken.isEmpty] as [String: Any] },
                "models": modelCatalog, "notice": message]
    }
    static func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: AINoRedirect(), delegateQueue: nil); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 8_000_000 else { throw CourseFailure(message: "登入服務回應無效") }
        return (data, response)
    }
    private func json(_ url: URL, form: [String: String]? = nil, token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        if let form {
            request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var parts = URLComponents(); parts.queryItems = form.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
            // URL query encoding leaves '+' literal; form encoding must escape it.
            request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await http(request)
        guard (200..<300).contains(response.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = body?["error"] as? String ?? (body?["error"] as? [String: Any])?["code"] as? String ?? ""
            if ["invalid_grant", "invalid_token"].contains(code) { throw CourseFailure(message: "ChatGPT 授權已失效，請選擇此帳號並重新登入") }
            if code == "access_denied" { throw CourseFailure(message: "未授權 ChatGPT 方案使用，請重新登入並允許使用方案") }
            throw CourseFailure(message: "ChatGPT 服務未完成請求（HTTP \(response.statusCode)）；請稍後重試")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CourseFailure(message: "ChatGPT 服務回應格式無效") }
        return json
    }
    private func discovery() async throws -> [String: Any] {
        let document = try await json(URL(string: Self.issuer + "/.well-known/openid-configuration")!)
        guard document["issuer"] as? String == Self.issuer else { throw CourseFailure(message: "OpenAI 登入服務身分不符") }
        return document
    }
    private func endpoint(_ document: [String: Any], _ key: String) throws -> URL {
        guard let text = document[key] as? String, let url = URL(string: text), url.scheme == "https", url.host == "auth.openai.com", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else {
            throw CourseFailure(message: "OpenAI 登入服務網址無效")
        }
        return url
    }
    func cancelLogin() { attempt = nil; callback?.cancel(); callback = nil }
    func login(profileID: String? = nil, openBrowser: (URL) -> Bool = { NSWorkspace.shared.open($0) }) async throws {
        guard !loggingIn else { throw CourseFailure(message: "ChatGPT 登入已開啟，請完成或取消") }
        if let profileID, !configuration.profiles.contains(where: { $0.clientID == profileID }) { throw CourseFailure(message: "帳號不存在") }
        let previous = configuration.profiles.first { $0.clientID == profileID }
        // Persist host identity before requesting dynamic registration.
        try save(configuration)
        let id = UUID(); attempt = id
        defer { if attempt == id { attempt = nil; callback?.cancel(); callback = nil } }
        let state = try OpenAIIdentity.random(), nonce = try OpenAIIdentity.random(), verifier = try OpenAIIdentity.random()
        let document = try await discovery()
        try checkAttempt(id)
        let listener = try OAuthLoopback(state: state); callback = listener
        let redirect = try await listener.start()
        var url = URLComponents(url: try endpoint(document, "authorization_endpoint"), resolvingAgainstBaseURL: false)!
        var parameters = ["client_id": previous?.clientID ?? "dynamic_agent_client", "ext_agent_host_id": configuration.hostID,
                          "response_type": "code", "redirect_uri": redirect.absoluteString,
                          "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", "resource": Self.resource,
                          "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": OpenAIIdentity.challenge(verifier)]
        if let previous {
            if !previous.idToken.isEmpty { parameters["id_token_hint"] = previous.idToken }
            if !previous.email.isEmpty { parameters["login_hint"] = previous.email }
        } else { parameters["agent_name_hint"] = "LearningShelf" }
        url.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        try checkAttempt(id)
        guard let browserURL = url.url, openBrowser(browserURL) else { throw CourseFailure(message: "無法開啟瀏覽器，請重試") }
        let returned = try await listener.result(); try checkAttempt(id)
        if returned["error"] != nil { throw CourseFailure(message: "登入已取消或未獲授權；原有帳號保持不變") }
        guard let code = returned["code"], !code.isEmpty else { throw CourseFailure(message: "登入回傳缺少授權碼") }
        let clientID = try Self.issuedClient(returned: returned["client_id"], previous: previous?.clientID)
        if previous == nil {
            var next = configuration
            if !next.profiles.contains(where: { $0.clientID == clientID }) { next.profiles.append(ChatGPTProfile(clientID: clientID)) }
            try save(next)
        }
        let response = try await json(try endpoint(document, "token_endpoint"), form: ["grant_type": "authorization_code", "client_id": clientID,
                    "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString, "resource": Self.resource])
        try checkAttempt(id)
        guard let idToken = response["id_token"] as? String else { throw CourseFailure(message: "登入未提供身分驗證") }
        let keys = try await json(try endpoint(document, "jwks_uri"))
        let claims = try OpenAIIdentity.verify(idToken, jwks: keys, clientID: clientID, nonce: nonce)
        if let previous, !previous.subject.isEmpty, previous.subject != claims["sub"] as? String { throw CourseFailure(message: "登入帳號與原先選擇的帳號不符") }
        var profile = try Self.credentials(response, previous: previous ?? ChatGPTProfile(clientID: clientID))
        if response["scope"] == nil { profile.scopes = [] }
        profile.subject = claims["sub"] as! String; profile.email = claims["email"] as? String ?? ""; profile.idToken = idToken
        try checkAttempt(id)
        var next = configuration; next.profiles.removeAll { $0.clientID == clientID }; next.profiles.append(profile)
        next.selectedProfileID = clientID; next.chatGPTModel = ""; try save(next); modelCatalog = []
        notice = profile.enabled ? "已登入並授權使用 ChatGPT 方案。" : "已登入，但尚未授權使用 ChatGPT 方案。請在 ChatGPT 管理使用權限。"
    }
    private func checkAttempt(_ id: UUID) throws { guard attempt == id, !Task.isCancelled else { throw CancellationError() } }
    static func issuedClient(returned: String?, previous: String?) throws -> String {
        if let previous { guard returned == nil || returned == previous else { throw CourseFailure(message: "登入回傳的帳號註冊不符") }; return previous }
        guard let returned, returned != "dynamic_agent_client", returned.range(of: "^[A-Za-z0-9._:-]{1,256}$", options: .regularExpression) != nil else { throw CourseFailure(message: "ChatGPT 註冊尚未完成，請重試") }
        return returned
    }
    static func credentials(_ response: [String: Any], previous: ChatGPTProfile) throws -> ChatGPTProfile {
        guard let access = response["access_token"] as? String, !access.isEmpty,
              (response["token_type"] as? String)?.lowercased() == "bearer",
              let lifetime = response["expires_in"] as? Double, lifetime > 0 else { throw CourseFailure(message: "ChatGPT 未提供有效登入憑證") }
        var profile = previous; profile.accessToken = access; profile.expiresAt = Date().addingTimeInterval(lifetime)
        if let token = response["refresh_token"] as? String { profile.refreshToken = token }
        if let scope = response["scope"] as? String { profile.scopes = scope.split(separator: " ").map(String.init) }
        return profile
    }
    func authorizedProfile(_ id: String) async throws -> ChatGPTProfile {
        guard let profile = configuration.profiles.first(where: { $0.clientID == id }), profile.enabled else { throw CourseFailure(message: "請先登入 ChatGPT 並授權使用方案") }
        if profile.expiresAt > Date().addingTimeInterval(60) { return profile }
        if let task = refreshes[id] { return try await task.value }
        guard !profile.refreshToken.isEmpty else { throw CourseFailure(message: "ChatGPT 登入已到期，請重新登入") }
        let task = Task<ChatGPTProfile, Error> {
            let lease = try AIRefreshLease(directory: self.files.directory); defer { lease.release() }
            if let bytes = try self.files.read("connection.json") {
                let saved = try JSONDecoder().decode(AIConfiguration.self, from: bytes)
                if let current = saved.profiles.first(where: { $0.clientID == id }), current.refreshToken != profile.refreshToken {
                    // Another process already rotated the token. Reload instead of replaying the old one.
                    self.configuration = saved
                    guard current.enabled, current.expiresAt > Date() else { throw CourseFailure(message: "ChatGPT 登入已變更，請重新登入") }
                    return current
                }
            }
            let response = try await self.json(URL(string: Self.issuer + "/api/accounts/oauth/token")!, form: ["grant_type": "refresh_token", "client_id": id, "refresh_token": profile.refreshToken, "resource": Self.resource])
            try Task.checkCancellation()
            var updated = try Self.credentials(response, previous: profile)
            if let token = response["id_token"] as? String {
                let document = try await self.discovery(), keys = try await self.json(try self.endpoint(document, "jwks_uri"))
                let claims = try OpenAIIdentity.verify(token, jwks: keys, clientID: id)
                guard claims["sub"] as? String == profile.subject else { throw CourseFailure(message: "ChatGPT 更新登入身分不符") }
                updated.idToken = token
            }
            var next = self.configuration
            try Task.checkCancellation()
            guard let index = next.profiles.firstIndex(where: { $0.clientID == id }), next.profiles[index].refreshToken == profile.refreshToken else { throw CancellationError() }
            next.profiles[index] = updated; try self.save(next)
            guard updated.enabled else { throw CourseFailure(message: "ChatGPT 方案使用權限已撤銷，請重新授權") }
            return updated
        }
        refreshes[id] = task; defer { refreshes.removeValue(forKey: id) }
        return try await task.value
    }
    func models() async throws {
        guard let id = selected?.clientID else { throw CourseFailure(message: "請先登入 ChatGPT") }
        let profile = try await authorizedProfile(id)
        let response = try await json(URL(string: Self.resource + "/models")!, token: profile.accessToken)
        guard configuration.selectedProfileID == id else { throw CancellationError() }
        let choices = (response["models"] as? [[String: Any]] ?? []).filter { $0["visibility"] as? String == "list" }.compactMap { model -> [String: String]? in
            guard let slug = model["slug"] as? String, let name = model["display_name"] as? String else { return nil }
            return ["slug": slug, "display_name": name]
        }
        guard !choices.isEmpty else { throw CourseFailure(message: "此 ChatGPT 帳號目前沒有可用模型；請檢查方案與授權") }
        modelCatalog = choices
        if !choices.contains(where: { $0["slug"] == configuration.chatGPTModel }) { try selectModel(choices[0]["slug"]!) }
    }
    func logout() async throws {
        guard let profile = selected else { return }
        cancelLogin(); refreshes.removeValue(forKey: profile.clientID)?.cancel()
        var confirmed = profile.refreshToken.isEmpty
        if !profile.refreshToken.isEmpty {
            do {
                let document = try await discovery(), url = try endpoint(document, "revocation_endpoint")
                // Revocation succeeds with an empty HTTP 200, rather than a JSON response.
                var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "token", value: profile.refreshToken), URLQueryItem(name: "token_type_hint", value: "refresh_token"), URLQueryItem(name: "client_id", value: profile.clientID)]
                var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
                for retry in 0..<2 {
                    do { let (_, response) = try await http(request); confirmed = response.statusCode == 200; if confirmed || response.statusCode < 500 { break } } catch { if retry == 1 { break } }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch { confirmed = false }
        }
        var next = configuration
        if let index = next.profiles.firstIndex(where: { $0.clientID == profile.clientID }) {
            next.profiles[index].accessToken = ""; next.profiles[index].refreshToken = ""; next.profiles[index].idToken = ""; next.profiles[index].scopes = []
        }
        try save(next); modelCatalog = []
        notice = confirmed ? "已登出 ChatGPT；API Key 設定仍保留。" : "已在此 Mac 登出；未能確認遠端撤銷，請到 ChatGPT 設定中中斷此 App 的連線。"
    }
    /// The host snapshots this transport per question. Changing provider never retries against a paid API key.
    func transport(profileID: String) -> HostSession.Transport {
        return { [weak self] request, completion in
            let task = Task { @MainActor in
                do {
                    guard let self else { throw CancellationError() }
                    let profile = try await self.authorizedProfile(profileID)
                    try Task.checkCancellation()
                    var request = request; request.setValue("Bearer " + profile.accessToken, forHTTPHeaderField: "Authorization")
                    let result = try await self.streamer(request)
                    try Task.checkCancellation(); completion(.success(result))
                } catch { completion(.failure(error)) }
            }
            return { task.cancel() }
        }
    }
    static func stream(_ request: URLRequest) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral; configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: AINoRedirect(), delegateQueue: nil); defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CourseFailure(message: "ChatGPT 回應無效") }
        guard (200..<300).contains(response.statusCode) else {
            throw CourseFailure(message: response.statusCode == 401 ? "ChatGPT 授權失效，請重新登入" : response.statusCode == 429 ? "ChatGPT 使用額度或速率已達上限，請稍後重試或自行切換 API Key" : "ChatGPT 請求失敗（HTTP \(response.statusCode)）")
        }
        // AsyncBytes.lines omits empty lines on supported macOS versions. SSE needs those
        // separators, so decode UTF-8 lines ourselves without losing event boundaries.
        var parser = ResponsesStream(), line = Data(), count = 0
        for try await byte in bytes {
            count += 1
            guard count <= 8_000_000, line.count <= 1_000_000 else { throw CourseFailure(message: "ChatGPT 回答超過可處理範圍") }
            if byte == 10 {
                try Task.checkCancellation()
                if line.last == 13 { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { throw CourseFailure(message: "ChatGPT 串流文字格式無效") }
                if let result = try parser.line(text) { return result }
                line.removeAll(keepingCapacity: true)
            } else { line.append(byte) }
        }
        throw CourseFailure(message: "ChatGPT 回答連線中斷，未收到完成事件；請重試")
    }
}

/// Bounded SSE parsing. Text deltas alone never count as a completed answer.
struct ResponsesStream {
    private var payload: [String] = []
    private var count = 0
    mutating func line(_ line: String) throws -> [String: Any]? {
        count += line.utf8.count
        guard count <= 8_000_000 else { throw CourseFailure(message: "ChatGPT 回答超過可處理範圍") }
        if !line.isEmpty {
            if line.hasPrefix("data:") { payload.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        defer { payload.removeAll(keepingCapacity: true) }
        guard !payload.isEmpty else { return nil }
        let data = Data(payload.joined(separator: "\n").utf8)
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CourseFailure(message: "ChatGPT 串流格式無效") }
        switch event["type"] as? String {
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else { throw CourseFailure(message: "ChatGPT 尚未完成回答") }
            return response
        case "response.incomplete": throw CourseFailure(message: "ChatGPT 回答未完成（輸出限制或中斷），請縮小問題後重試")
        case "response.failed", "error":
            let response = event["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
            let code = error["code"] as? String ?? ""
            if ["subscription_sharing_usage_limit_exceeded", "subscription_sharing_usage_unavailable"].contains(code) {
                throw CourseFailure(message: "ChatGPT 方案額度已達上限或暫不可用。請查看使用量，稍後重試或自行切換 API Key。")
            }
            throw CourseFailure(message: "ChatGPT 未完成回答，請檢查授權並重試")
        default: return nil
        }
    }
}

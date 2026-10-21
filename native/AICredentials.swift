import Foundation
import Security
import CryptoKit

/// Credentials live outside the app bundle and learner exports. This location survives app replacement.
struct AICredentialFiles {
    let directory: URL
    func read(_ name: String) throws -> Data? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func write(_ data: Data, name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Set permissions before renaming, so a newly written secret is never world-readable.
        let temporary = directory.appendingPathComponent("." + UUID().uuidString)
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CourseFailure(message: "無法保存 AI 登入設定")
        }
        defer { try? fm.removeItem(at: temporary) }
        guard rename(temporary.path, directory.appendingPathComponent(name).path) == 0 else {
            throw CourseFailure(message: "無法更新 AI 登入設定")
        }
    }
    func remove(_ name: String) throws {
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Never replay a rotating refresh token from two running copies of the app.
final class AIRefreshLease {
    private var descriptor: Int32
    init(directory: URL) throws {
        descriptor = open(directory.appendingPathComponent("refresh.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CourseFailure(message: "無法鎖定 ChatGPT 登入設定") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw CourseFailure(message: "另一個 LearningShelf 正在更新 ChatGPT 登入，請稍後重試")
        }
    }
    func release() { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 } }
    deinit { release() }
}

final class AINoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum OpenAIIdentity {
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ text: String) -> Data? {
        let value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CourseFailure(message: "無法建立安全登入請求")
        }
        return base64URL(Data(bytes))
    }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    private static func der(_ tag: UInt8, _ bytes: Data) -> Data {
        let length = bytes.count
        let encodedLength: [UInt8] = length < 128 ? [UInt8(length)] : length < 256 ? [0x81, UInt8(length)] : [0x82, UInt8(length >> 8), UInt8(length & 255)]
        return Data([tag] + encodedLength) + bytes
    }
    private static func integer(_ data: Data) -> Data {
        var bytes = data
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        if (bytes.first ?? 0) & 0x80 != 0 { bytes.insert(0, at: 0) }
        return der(0x02, bytes)
    }
    /// Only a verified ID token may supply identity. Access tokens are opaque bearer credentials.
    static func verify(_ token: String, jwks: [String: Any], clientID: String, nonce: String? = nil, now: Date = Date()) throws -> [String: Any] {
        let failure = CourseFailure(message: "ChatGPT 身分驗證失敗，請重新登入")
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = decode(parts[0]), let payloadData = decode(parts[1]), let signature = decode(parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256",
              header["crit"] == nil,
              let kid = header["kid"] as? String,
              let jwk = (jwks["keys"] as? [[String: Any]])?.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              jwk["use"] == nil || jwk["use"] as? String == "sig", jwk["alg"] == nil || jwk["alg"] as? String == "RS256",
              let n = (jwk["n"] as? String).flatMap(decode), n.count >= 256, n.count <= 1024,
              let e = (jwk["e"] as? String).flatMap(decode), e.count <= 8,
              let key = SecKeyCreateWithData(der(0x30, integer(n) + integer(e)) as CFData,
                    [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              claims["iss"] as? String == "https://auth.openai.com",
              let sub = claims["sub"] as? String, !sub.isEmpty,
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970,
              (claims["aud"] as? String == clientID || (claims["aud"] as? [String])?.contains(clientID) == true),
              nonce == nil || claims["nonce"] as? String == nonce else { throw failure }
        if let party = claims["azp"] as? String, party != clientID { throw failure }
        if let aud = claims["aud"] as? [String], aud.count > 1, claims["azp"] as? String != clientID { throw failure }
        if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 + 30 { throw failure }
        return claims
    }
}

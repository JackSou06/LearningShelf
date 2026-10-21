import Foundation

struct AuthoringTokenCounts: Codable, Equatable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
    var cacheWriteInputTokens: Int?
    init?(_ value: [String: Any]?) {
        guard let value, let input = value["inputTokens"] as? Int, let cached = value["cachedInputTokens"] as? Int,
              let output = value["outputTokens"] as? Int, let reasoning = value["reasoningOutputTokens"] as? Int,
              let total = value["totalTokens"] as? Int, [input, cached, output, reasoning, total].allSatisfy({ $0 >= 0 }) else { return nil }
        inputTokens = input; cachedInputTokens = cached; outputTokens = output; reasoningOutputTokens = reasoning; totalTokens = total
        cacheWriteInputTokens = value["cacheWriteInputTokens"] as? Int
    }
}
struct AuthoringUsage: Codable {
    var threadID: String
    var turnID: String
    var stage: String
    var total: AuthoringTokenCounts
    var last: AuthoringTokenCounts
}

enum AuthoringCheckpoints {
    static func cachedManifest(job: URL, sources: [AuthoringSource], trustedManifest: AuthoringInputManifest?) -> AuthoringInputManifest? {
        // Existing manifests from older builds are intentionally prepared once using this revision.
        guard let version = try? String(contentsOf: job.appendingPathComponent("input-preparation.version"), encoding: .utf8), version == "1920-jpeg84-v1",
              let manifest = trustedManifest,
              manifest.sources.count == sources.count else { return nil }
        // The model can edit work/input; trust only the App-owned manifest saved outside its sandbox.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let current = try? AuthoringMaterials.read(AuthoringInputManifest.self, from: AuthoringVisuals.safeURL("input/sources.json", under: job)),
              (try? encoder.encode(current)) == (try? encoder.encode(manifest)) else { return nil }
        for (source, frozen) in zip(manifest.sources, sources) {
            guard source.file == frozen.file, source.sha256 == frozen.sha256, source.kind == frozen.kind,
                  (try? AuthoringMaterials.hash(AuthoringVisuals.safeURL(source.file, under: job))) == frozen.sha256 else { return nil }
            for page in source.pages {
                guard (try? AuthoringMaterials.hash(AuthoringVisuals.safeURL(page.image, under: job))) == page.sha256 else { return nil }
            }
            if ["pdf", "pptx"].contains(source.kind) {
                let transcript = "input/rendered/" + URL(fileURLWithPath: source.file).lastPathComponent + ".txt"
                guard let url = try? AuthoringVisuals.safeURL(transcript, under: job), FileManager.default.fileExists(atPath: url.path) else { return nil }
            }
            if let hash = source.renderedPDFSHA256 {
                let file = "input/converted/" + URL(fileURLWithPath: source.file).deletingPathExtension().lastPathComponent + ".pdf"
                guard (try? AuthoringMaterials.hash(AuthoringVisuals.safeURL(file, under: job))) == hash else { return nil }
            }
        }
        return manifest
    }
    static func cropKey(_ crop: AuthoringVisuals.Preview) -> String { crop.topicId + ":" + crop.imageBlockId }
    static func cropSignature(_ crop: AuthoringVisuals.Preview, job: URL) throws -> String {
        let root = try AuthoringVisuals.safeURL("course", under: job)
        let course = try AuthoringCompiler.object(AuthoringVisuals.safeURL("course.json", under: root))
        guard let ref = (course["topics"] as? [[String: Any]])?.first(where: { $0["id"] as? String == crop.topicId }), let file = ref["file"] as? String else { throw AuthoringFailure("裁圖的主題不存在。") }
        let topic = try AuthoringCompiler.object(AuthoringVisuals.safeURL(file, under: root))
        let map = try AuthoringCompiler.object(AuthoringVisuals.safeURL("IMAGE_MAP.json", under: root))
        let entry = (map["images"] as? [[String: Any]])?.first { $0["topicId"] as? String == crop.topicId && $0["imageBlockId"] as? String == crop.imageBlockId } ?? [:]
        let ids = Set((entry["detailBlockIds"] as? [String] ?? []) + (entry["teachingBlockIds"] as? [String] ?? []) + [crop.imageBlockId])
        let rulesHash = (try? AuthoringMaterials.hash(AuthoringVisuals.safeURL("rules/version.json", under: job))) ?? ""
        var parts = [AuthoringRules.revision, rulesHash, crop.sha256, crop.sourceImage, crop.sourceName, String(crop.page), crop.file]
        parts.append(String(data: try JSONSerialization.data(withJSONObject: crop.crop, options: [.sortedKeys]), encoding: .utf8)!)
        for var b in (topic["blocks"] as? [[String: Any]] ?? []).sorted(by: { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }) where ids.contains(b["id"] as? String ?? "") {
            // Display changes don't alter the observed pixels; captions/details/teaching do.
            b.removeValue(forKey: "display")
            parts.append(String(data: try JSONSerialization.data(withJSONObject: b, options: [.sortedKeys]), encoding: .utf8)!)
            if b["type"] as? String == "markdown", let file = b["file"] as? String { parts.append(try AuthoringMaterials.hash(AuthoringVisuals.safeURL(file, under: root))) }
        }
        return AuthoringMaterials.hash(Data(parts.joined(separator: "\n").utf8))
    }
    static func reviews(job: URL) -> [String: String] { (try? AuthoringMaterials.read([String: String].self, from: job.appendingPathComponent("crop-reviews.json"))) ?? [:] }
    static func pending(_ crops: [AuthoringVisuals.Preview], job: URL) throws -> [AuthoringVisuals.Preview] {
        let saved = reviews(job: job)
        return try crops.filter { saved[cropKey($0)] != (try cropSignature($0, job: job)) }
    }
    static func record(_ crops: [AuthoringVisuals.Preview], job: URL) throws {
        var saved = reviews(job: job)
        for crop in crops { saved[cropKey(crop)] = try cropSignature(crop, job: job) }
        try AuthoringMaterials.write(saved, to: job.appendingPathComponent("crop-reviews.json"))
    }
}

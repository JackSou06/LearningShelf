import Foundation
import JavaScriptCore

struct CourseFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
struct LoadedCourse {
    let token = UUID()
    let root: URL
    let pack: [String: Any]
    let model: [String: Any]
    var id: String { model["courseId"] as! String }
    var title: String { model["title"] as! String }
    var version: String { model["contentVersion"] as! String }
    var topicCount: Int { (model["topics"] as? [[String: Any]])?.count ?? 0 }
}
final class CourseLoader {
    static let maximumContentBytes = 100_000_000
    let context: JSContext
    init(webRoot: URL) throws {
        guard let context = JSContext() else { throw CourseFailure(message: "無法啟動格式驗證器") }
        self.context = context
        context.evaluateScript(try String(contentsOf: webRoot.appendingPathComponent("course-core.js"), encoding: .utf8))
        if let error = context.exception { throw CourseFailure(message: "驗證器錯誤：\(error)") }
    }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.count < 1024 && !path.hasPrefix("/") && path.rangeOfCharacter(from: CharacterSet(charactersIn: "\\?#:%").union(.controlCharacters)) == nil && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func resource(_ path: String, root: URL) throws -> URL {
        guard safePath(path) else { throw CourseFailure(message: "不安全的檔案路徑：\(path)") }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: url.path) else { throw CourseFailure(message: "找不到課程內檔案：\(path)") }
        return url
    }
    func load(_ root: URL) throws -> LoadedCourse {
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        let url = try Self.resource("course.json", root: root)
        var files: [String: String] = [:], available: [String: Bool] = [:], assets: [String: String] = [:]
        var total = 0, loaded = Set<String>()
        func read(_ path: String, json: Bool = false) throws -> Any? {
            if loaded.contains(path) { return json ? try JSONSerialization.jsonObject(with: Data(files[path]!.utf8)) : nil }
            let u = try Self.resource(path, root: root)
            let values = try u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw CourseFailure(message: "必須是一般檔案：\(path)") }
            available[path] = true; loaded.insert(path)
            let ext = u.pathExtension.lowercased()
            if ["json", "md", "png", "jpg", "jpeg", "webp"].contains(ext) {
                total += values.fileSize ?? 0
                guard total <= Self.maximumContentBytes else { throw CourseFailure(message: "課程文字與圖片超過 100 MB") }
                let data = try Data(contentsOf: u)
                if ["json", "md"].contains(ext) { files[path] = String(data: data, encoding: .utf8); guard files[path] != nil else { throw CourseFailure(message: "需使用 UTF-8：\(path)") } }
                else { assets[path] = "data:image/\(ext == "jpg" ? "jpeg" : ext);base64," + data.base64EncodedString() }
                if json { return try JSONSerialization.jsonObject(with: data) }
            }
            return nil
        }
        guard let manifest = try read("course.json", json: true) as? [String: Any] else { throw CourseFailure(message: "course.json 必須是物件") }
        for entry in manifest["topics"] as? [[String: Any]] ?? [] {
            guard let path = entry["file"] as? String else { continue }
            if let topic = try read(path, json: true) as? [String: Any] {
                for block in topic["blocks"] as? [[String: Any]] ?? [] {
                    if let p = block["file"] as? String { _ = try read(p) }
                }
            }
        }
        for appendix in manifest["archiveFiles"] as? [[String: Any]] ?? [] {
            if let p = appendix["file"] as? String { _ = try read(p) }
        }
        for source in manifest["sources"] as? [[String: Any]] ?? [] {
            if let p = source["file"] as? String { _ = try read(p) }
        }
        let pack: [String: Any] = ["files": files, "available": available, "assets": assets, "base": ""]
        context.exception = nil
        guard let result = context.objectForKeyedSubscript("CourseCore")?.forProperty("validate")?.call(withArguments: [pack])?.toDictionary() as? [String: Any], context.exception == nil else { throw CourseFailure(message: "教材結構無法解析；請檢查 JSON 欄位型別") }
        guard result["valid"] as? Bool == true, let model = result["course"] as? [String: Any] else {
            let report = try JSONSerialization.data(withJSONObject: ["errors": result["errors"] ?? []], options: [.prettyPrinted, .sortedKeys])
            throw CourseFailure(message: String(data: report, encoding: .utf8)!)
        }
        _ = url
        return LoadedCourse(root: root, pack: pack, model: model)
    }
}

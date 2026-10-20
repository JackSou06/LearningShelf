import Foundation
import AppKit
import PDFKit

@MainActor final class FixtureCodex: CodexAuthoringService {
    var onProgress: ((String) -> Void)?
    var onLoginCompleted: ((Bool) -> Void)?
    var ready = true, failConversionOnce = false, invalidForever = false, slowTutorial = false, omitTutorialOnce = false
    var counts: [String: Int] = [:]
    func connect(executable: URL) async throws {}
    func accountReady() async throws -> Bool { ready }
    func models() async throws -> [AuthoringModel] { [AuthoringModel(id: "fixture", title: "Fixture", effort: nil)] }
    func login() async throws -> URL { URL(string: "https://chatgpt.com/")! }
    func startThread(directory: URL, resume: String?) async throws -> String { resume ?? "fixture-thread" }
    func stop() {}
    func run(thread: String, prompt: String, directory: URL, model: AuthoringModel) async throws {
        let fm = FileManager.default
        let stage = prompt.contains("現在只完成") ? "tutorial" : prompt.contains("內部第二階段") ? "review" : prompt.contains("原生驗證未通過") ? "repair" : "conversion"
        counts[stage, default: 0] += 1; onProgress?("fixture " + stage)
        if stage == "tutorial" {
            if omitTutorialOnce { omitTutorialOnce = false; return }
            if slowTutorial { try await Task.sleep(nanoseconds: 20_000_000_000) }
            try fm.createDirectory(at: directory.appendingPathComponent("draft"), withIntermediateDirectories: true)
            try "# 完整教學\n\n兩個量相加。\n\n例如 1 + 2 = 3，先取 1 再加 2。\n\n自我檢查：2 + 1？理由是交換兩個加數不改變總和，答案為3。\n".write(to: directory.appendingPathComponent("draft/tutorial.md"), atomically: true, encoding: .utf8)
        } else if stage == "review" {
            try "已重算1+2與2+1；教學段落先說明操作再給例子與理由。此為整合測試fixture，未聲稱真實教學效果。".write(to: directory.appendingPathComponent("draft/review.md"), atomically: true, encoding: .utf8)
        } else {
            if failConversionOnce && stage == "conversion" { failConversionOnce = false; throw AuthoringFailure("fixture interrupted conversion") }
            try makeCourse(directory, valid: !invalidForever && stage == "repair")
        }
    }
    func makeCourse(_ work: URL, valid: Bool) throws {
        let fm = FileManager.default, root = work.appendingPathComponent("course")
        for f in ["topics", "sources"] { try fm.createDirectory(at: root.appendingPathComponent(f), withIntermediateDirectories: true) }
        let contract = try String(contentsOf: work.appendingPathComponent("OUTPUT_CONTRACT.md"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"courseId="([^"]+)""#), match = regex.firstMatch(in: contract, range: NSRange(contract.startIndex..., in: contract))!
        let id = String(contract[Range(match.range(at: 1), in: contract)!])
        let input = try AuthoringMaterials.read(AuthoringInputManifest.self, from: work.appendingPathComponent("input/sources.json"))
        func copy(_ a: URL, _ b: URL) throws { if fm.fileExists(atPath: b.path) { try fm.removeItem(at: b) }; try fm.copyItem(at: a, to: b) }
        try copy(work.appendingPathComponent("draft/tutorial.md"), root.appendingPathComponent("sources/tutorial.md"))
        try copy(work.appendingPathComponent("draft/tutorial.md"), root.appendingPathComponent("topics/body.md"))
        for s in input.sources { try copy(work.appendingPathComponent(s.file), root.appendingPathComponent("sources/" + URL(fileURLWithPath: s.file).lastPathComponent)) }
        let manifest: [String: Any] = ["schemaVersion": "1.1", "courseId": valid ? id : "incorrect-id", "contentVersion": "1.0.0", "title": "自動製作測試", "language": "zh-Hant", "modules": [["id": "module", "title": "教學", "topics": ["topic"]]], "topics": [["id": "topic", "file": "topics/topic.json"]], "sources": [["id": "fixture", "kind": "reference", "title": "自編整合測試"]]]
        let topic: [String: Any] = ["id": "topic", "title": "加法", "blocks": [["id": "body", "type": "markdown", "file": "topics/body.md"]]]
        let lineCount = try String(contentsOf: work.appendingPathComponent("draft/tutorial.md"), encoding: .utf8).components(separatedBy: "\n").count
        let coverage: [String: Any] = ["tutorialSha256": try AuthoringMaterials.hash(work.appendingPathComponent("draft/tutorial.md")), "segments": [["startLine": 1, "endLine": lineCount, "topicId": "topic", "blockIds": ["body"]]]]
        for (name, value) in [("course.json", manifest), ("topics/topic.json", topic), ("TEACHING_COVERAGE.json", coverage), ("IMAGE_MAP.json", ["images": []])] {
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: root.appendingPathComponent(name))
        }
    }
}

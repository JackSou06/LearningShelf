import Foundation
import AppKit

@MainActor final class PlanCodex: CodexAuthoringService {
    var onProgress: ((String) -> Void)?
    var onLoginCompleted: ((Bool) -> Void)?
    var onUsage: ((AuthoringUsage) -> Void)?
    var counts: [String: Int] = [:]
    var failVisualOnce = false, changeCropOnce = false
    var efforts: [String: String] = [:]
    let base = FixtureCodex()
    func connect(executable: URL) async throws {}
    func accountReady() async throws -> Bool { true }
    func models() async throws -> [AuthoringModel] { [AuthoringModel(id: "fixture", title: "Fixture", effort: "high", supportedEfforts: ["high", "medium"])] }
    func login() async throws -> URL { URL(string: "https://chatgpt.com/")! }
    func startThread(directory: URL, resume: String?) async throws -> String { resume ?? UUID().uuidString }
    func stop() {}
    func run(thread: String, prompt: String, directory: URL, model: AuthoringModel) async throws {
        let stage = prompt.contains("最終裁圖視覺核對") ? "visual" : prompt.contains("內部第一階段") ? "tutorial" : prompt.contains("內部第二階段") ? "review" : prompt.contains("原生驗證未通過") ? "repair" : "conversion"
        counts[stage, default: 0] += 1; efforts[stage] = model.effort ?? ""
        let n = counts.values.reduce(0,+)
        let total = AuthoringTokenCounts(["inputTokens": n * 100, "cachedInputTokens": n * 60, "outputTokens": n * 20, "reasoningOutputTokens": n * 5, "totalTokens": n * 120])!
        let last = AuthoringTokenCounts(["inputTokens": 100, "cachedInputTokens": 60, "outputTokens": 20, "reasoningOutputTokens": 5, "totalTokens": 120])!
        let usage = AuthoringUsage(threadID: thread, turnID: "turn-\(n)", stage: "", total: total, last: last)
        onUsage?(usage); onUsage?(usage) // duplicate notifications must not double count
        if stage == "tutorial" || stage == "review" { try await base.run(thread: thread, prompt: prompt, directory: directory, model: model); return }
        if stage == "visual" {
            if failVisualOnce { failVisualOnce = false; throw AuthoringFailure("fixture service unavailable") }
            let pending = try AuthoringMaterials.read(AuthoringVisuals.Result.self, from: directory.appendingPathComponent("PENDING_CROP_REVIEWS.json"))
            precondition(pending.crops.count == 1 && NSImage(contentsOf: directory.appendingPathComponent("course/" + pending.crops[0].file)) != nil)
            if changeCropOnce {
                changeCropOnce = false
                let url = directory.appendingPathComponent("course/IMAGE_MAP.json")
                var map = try AuthoringCompiler.object(url), entries = map["images"] as! [[String: Any]]
                entries[entries.count - 1]["crop"] = ["x": 0.05, "y": 0.23, "width": 0.34, "height": 0.41]
                map["images"] = entries; try AuthoringCompiler.save(map, url)
            }
            return
        }
        if stage == "repair" { fatalError("Native plan fixture should need no content repairs") }
        let source = try AuthoringMaterials.read(AuthoringInputManifest.self, from: directory.appendingPathComponent("input/sources.json"))
        let lineCount = try String(contentsOf: directory.appendingPathComponent("draft/tutorial.md"), encoding: .utf8).components(separatedBy: "\n").count
        var blocks: [[String: Any]] = [["id": "body", "type": "markdown", "tutorialLines": [1,lineCount]],
            ["id": "example-code", "type": "code", "language": "python", "code": "print(1 + 2)"],
            ["id": "self-check", "type": "reveal", "prompt": "1+2？", "answerMarkdown": "3，將兩個量相加。"],
            ["id": "formula", "type": "math", "latex": "1+2=3", "description": "加法例子"],
            ["id": "table", "type": "table", "columns": ["輸入","結果"], "rows": [["1+2","3"]]],
            ["id": "choice", "type": "singleChoice", "question": "1+2？", "options": [["id":"a","text":"3"],["id":"b","text":"4"]], "answerId":"a", "explanation":"相加得到3。"],
            ["id": "flow", "type":"diagram", "layout":"flow", "nodes":[["kicker":"起點","title":"兩個量","detailMarkdown":"1和2"],["kicker":"結果","title":"相加","detailMarkdown":"得到3"]]],
            ["id": "steps", "type":"steps", "steps":[["id":"step-1","title":"相加","bodyMarkdown":"將1和2相加得到3。"]]],
            ["id": "position", "type":"filePosition", "initialText":"ABC", "maxOffset":10],
            ["id": "count", "type":"callCount", "bytes":8, "buffers":[1,4], "initialBuffer":1]]
        for (i,page) in source.sources.flatMap(\.pages).enumerated() {
            blocks += [["id": "page-\(i)", "type": "image", "sourceImage": page.image, "alt": "原頁\(page.page)", "description": "測試原頁，含圖例與公式。", "detailBlockIds": ["detail-\(i)"], "teachingBlockIds": ["reading-\(i)"]],
                ["id": "reading-\(i)", "type": "markdown", "text": "這是原頁圖例的相鄰解釋。"],
                ["id": "detail-\(i)", "type": "markdown", "visibility": "contextOnly", "text": "測試來源圖：白底、黑色求和文字、綠色矩形與紅色橢圓。測試替身資料，不宣稱真實模型看圖。"]]
        }
        let first = source.sources.flatMap(\.pages)[0]
        blocks += [["id": "crop", "type": "image", "file": "assets/crop.png", "sourceImage": first.image, "crop": ["x":0.06,"y":0.24,"width":0.32,"height":0.39], "alt": "綠色矩形局部", "description": "第1頁局部", "detailBlockIds": ["crop-detail"], "teachingBlockIds": ["crop-reading"]],
            ["id": "crop-reading", "type": "markdown", "text": "觀察下圖綠色矩形，沒有標示長度，不能憑外觀推算數值。"],
            ["id": "crop-detail", "type": "markdown", "visibility": "contextOnly", "text": "裁圖中綠色矩形四周留白；文字與紅色橢圓在裁圖外。標記意圖未知。"]]
        let plan: [String: Any] = ["planVersion":1, "course":["title":"原生轉製測試", "language":"zh-Hant", "modules":[["id":"module","title":"教學","topics":["topic"]]]], "topics":[["id":"topic","title":"完整內容","blocks":blocks]]]
        try AuthoringCompiler.save(plan, directory.appendingPathComponent("draft/course-plan.json"))
    }
}

@main struct AuthoringOptimizationChecks {
    @MainActor static func main() async throws {
        func checked(_ condition: @autoclosure () throws -> Bool, _ message: String = "") throws { let passed = try condition(); precondition(passed, message) }
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2]), pdf = URL(fileURLWithPath: CommandLine.arguments[3])
        let fm = FileManager.default, temp = fm.temporaryDirectory.appendingPathComponent("learning-optimization-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("courses","Courses"),("protocol","Protocol")] { try fm.createSymbolicLink(at: resources.appendingPathComponent(b), withDestinationURL: repo.appendingPathComponent(a)) }
        let defaults = UserDefaults(suiteName: "optimization-" + UUID().uuidString)!; defaults.set("/usr/bin/true", forKey: "authoring.codexPath")
        let service = PlanCodex(), store = AppStore(resources: resources, dataDirectory: temp.appendingPathComponent("library"), transport: {_,_ in return {}})
        let author = CourseAuthoringStore(resources: resources, dataDirectory: temp.appendingPathComponent("jobs"), defaults: defaults, service: service)
        defer { author.shutdown() }
        author.setImporter { zip, folder in try await store.importGeneratedCourse(zip, destination: folder) }
        func wait() async throws { for _ in 0..<1500 { if !author.isBusy { return }; try await Task.sleep(nanoseconds: 20_000_000) }; fatalError("Job timeout") }
        let frozen = temp.appendingPathComponent("tutorial.md"), original = Data("# 指定教程\r\n\r\n保留這段原文。\r\n\r\n例子：1 + 2 = 3。\r\n".utf8)
        try original.write(to: frozen)
        author.create([pdf, frozen], destination: nil, useExistingTutorial: true); try await wait()
        let job = author.jobs[0]; precondition(job.stage == "completed", job.error ?? job.stage)
        precondition(service.counts["tutorial"] == nil && service.counts["review"] == 1 && service.counts["conversion"] == 1 && service.counts["visual"] == 1 && service.counts["repair"] == nil)
        precondition(service.efforts["review"] == "high" && service.efforts["conversion"] == "medium" && service.efforts["visual"] == "high")
        precondition(job.tokenUsage?.count == 3 && job.tokenUsage?.contains(where: { $0.stage == "visual" }) == true)
        let work = author.workDirectory(job.id), course = work.appendingPathComponent("course")
        try checked(try Data(contentsOf: course.appendingPathComponent("sources/tutorial.md")) == original)
        let topic = try AuthoringCompiler.object(course.appendingPathComponent("topics/topic.json")), blocks = topic["blocks"] as! [[String: Any]]
        precondition(Set(blocks.compactMap { $0["type"] as? String }).count == 11)
        let crop = blocks.first { $0["id"] as? String == "crop" }!
        precondition((crop["display"] as? [String: Any])?["widthPercent"] as? Int == 60)
        let manifest = try AuthoringMaterials.read(AuthoringInputManifest.self, from: work.appendingPathComponent("input/sources.json"))
        precondition(AuthoringCheckpoints.cachedManifest(job: work, sources: job.inputs, trustedManifest: job.preparedManifest) != nil)
        let inputMap = work.appendingPathComponent("input/sources.json"), inputBytes = try Data(contentsOf: inputMap)
        var forged = manifest; forged.sources[0].pages = []
        try AuthoringMaterials.write(forged, to: inputMap)
        precondition(AuthoringCheckpoints.cachedManifest(job: work, sources: job.inputs, trustedManifest: job.preparedManifest) == nil, "Model-edited manifest must not suppress source pages")
        try inputBytes.write(to: inputMap)
        let visuals = try AuthoringMaterials.read(AuthoringVisuals.Result.self, from: work.appendingPathComponent("CROP_PREVIEWS.json"))
        try checked(try AuthoringCheckpoints.pending(visuals.crops, job: work).isEmpty)
        let topicURL = course.appendingPathComponent("topics/topic.json"), saved = try Data(contentsOf: topicURL)
        var modified = topic, changedBlocks = blocks
        changedBlocks.reverse(); modified["blocks"] = changedBlocks; try AuthoringCompiler.save(modified, topicURL)
        try checked(try AuthoringCheckpoints.pending(visuals.crops, job: work).isEmpty, "Reordering unrelated blocks must not invalidate identical visual content")
        try saved.write(to: topicURL)
        let detail = course.appendingPathComponent("topics/topic/crop-detail.md"), detailBytes = try Data(contentsOf: detail)
        try "changed visual detail".write(to: detail, atomically: true, encoding: .utf8)
        try checked(try AuthoringCheckpoints.pending(visuals.crops, job: work).count == 1)
        try detailBytes.write(to: detail)
        let tutorialRules = try String(contentsOf: work.appendingPathComponent("rules/tutorial.md"), encoding: .utf8)
        precondition(!tutorialRules.contains("### 第三階段") && !tutorialRules.contains("### 第二階段") && !tutorialRules.contains("course.schema.json"))
        let planFile = work.appendingPathComponent("draft/course-plan.json"), planBytes = try Data(contentsOf: planFile), courseHash = try AuthoringMaterials.hash(course.appendingPathComponent("course.json"))
        var invalid = try AuthoringCompiler.object(planFile), invalidTopics = invalid["topics"] as! [[String: Any]], invalidBlocks = invalidTopics[0]["blocks"] as! [[String: Any]]
        invalidBlocks[0]["tutorialLines"] = [1,999999]; invalidTopics[0]["blocks"] = invalidBlocks; invalid["topics"] = invalidTopics
        try AuthoringCompiler.save(invalid, planFile)
        do { try AuthoringCompiler.materialize(job: work, manifest: manifest, courseID: job.courseID); fatalError("Accepted invalid tutorial range") } catch {}
        try checked(try AuthoringMaterials.hash(course.appendingPathComponent("course.json")) == courseHash, "Failed compilation must preserve previous artifacts")
        invalidBlocks[0].removeValue(forKey: "tutorialLines"); invalidBlocks[0]["contentFile"] = "../outside.md"; invalidTopics[0]["blocks"] = invalidBlocks; invalid["topics"] = invalidTopics
        try AuthoringCompiler.save(invalid, planFile)
        do { try AuthoringCompiler.materialize(job: work, manifest: manifest, courseID: job.courseID); fatalError("Accepted traversal") } catch {}
        try planBytes.write(to: planFile)
        // Changed coordinates trigger direct rerender/review, without a generic content repair.
        service.changeCropOnce = true; let beforeVisual = service.counts["visual", default:0]
        author.create([pdf], destination: nil); try await wait()
        precondition(author.jobs[0].stage == "completed", author.jobs[0].error ?? "failed")
        precondition(service.counts["visual"] == beforeVisual + 2 && service.counts["repair"] == nil)
        // A service failure is retained for user retry, not presented as invalid teaching.
        service.failVisualOnce = true; author.create([pdf], destination: nil); try await wait()
        let failed = author.jobs[0]; precondition(failed.stage == "failed" && failed.repairAttempts == 0)
        let conversionCount = service.counts["conversion"], tutorialCount = service.counts["tutorial"]
        author.resume(failed.id); try await wait()
        precondition(author.jobs[0].stage == "completed" && service.counts["conversion"] == conversionCount && service.counts["tutorial"] == tutorialCount)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let outputCourse = output.appendingPathComponent("course")
        if fm.fileExists(atPath: outputCourse.path) { try fm.removeItem(at: outputCourse) }
        try fm.copyItem(at: course, to: outputCourse)
        try AuthoringMaterials.write(job.tokenUsage ?? [], to: output.appendingPathComponent("usage-fixture.json"))
        print("Optimization passed: stage packets; frozen MD preserved; native plan compilation and auto-import; all existing block types retained; native hashes/coverage/reports; persistent visual checkpoints; changed-detail invalidation; crop changes rerender directly; service failure avoids content repairs; stage efforts and usage deduplication. Fixture Codex only.")
    }
}

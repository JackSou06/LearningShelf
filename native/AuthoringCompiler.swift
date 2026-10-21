import Foundation

/// A deterministic adapter for protocol blocks. It never invents or summarizes teaching.
enum AuthoringCompiler {
    static func object(_ url: URL) throws -> [String: Any] {
        let attr = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard attr.isRegularFile == true, attr.isSymbolicLink != true, (attr.fileSize ?? Int.max) <= 20_000_000,
              let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw AuthoringFailure("無效或過大的計畫／JSON：\(url.lastPathComponent)")
        }
        return value
    }
    static func save(_ value: Any, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
    }
    static func identifier(_ value: Any?) throws -> String {
        guard let id = value as? String, id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil else {
            throw AuthoringFailure("計畫的主題／區塊 ID 無效。")
        }
        return id
    }
    static func copy(_ source: URL, to target: URL) throws {
        let a = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard a.isRegularFile == true, a.isSymbolicLink != true else { throw AuthoringFailure("只接受一般內容檔案：\(source.lastPathComponent)") }
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: source, to: target)
    }

    /// Old jobs can finish their existing course artifacts. New jobs use a plan.
    @discardableResult static func materialize(job: URL, manifest: AuthoringInputManifest, courseID: String) throws -> Bool {
        let fm = FileManager.default, planFile = try AuthoringVisuals.safeURL("draft/course-plan.json", under: job)
        guard fm.fileExists(atPath: planFile.path) else { return false }
        let plan = try object(planFile)
        guard plan["planVersion"] as? Int == 1, var course = plan["course"] as? [String: Any],
              let topics = plan["topics"] as? [[String: Any]], !topics.isEmpty, topics.count <= 2000 else {
            throw AuthoringFailure("course-plan.json 需要 planVersion=1、course、topics。")
        }
        guard topics.reduce(0, { $0 + (($1["blocks"] as? [Any])?.count ?? 0) }) <= 10000 else { throw AuthoringFailure("計畫區塊過多，超過課程封裝容量。") }
        let tutorial = try AuthoringVisuals.safeURL("draft/tutorial.md", under: job)
        // Include referenced content, so changing a draft MD also invalidates compilation.
        var dependencies = [try AuthoringMaterials.hash(planFile), try AuthoringMaterials.hash(tutorial)]
        for t in topics { for b in t["blocks"] as? [[String: Any]] ?? [] {
            if let file = b["contentFile"] as? String { dependencies.append(try AuthoringMaterials.hash(AuthoringVisuals.safeURL(file, under: job))) }
        } }
        let digest = AuthoringMaterials.hash(Data(dependencies.joined(separator: "\n").utf8))
        let checkpoint = job.appendingPathComponent("compiled-plan.sha256"), dest = try AuthoringVisuals.safeURL("course", under: job)
        if (try? String(contentsOf: checkpoint, encoding: .utf8)) == digest, fm.fileExists(atPath: dest.appendingPathComponent("course.json").path) { return false }
        let stage = job.appendingPathComponent("compiled-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let lines = try String(contentsOf: tutorial, encoding: .utf8).components(separatedBy: "\n")
        var sources: [[String: Any]] = [], indexes: [[String: Any]] = [], segments: [[String: Any]] = [], images: [[String: Any]] = []
        for (i, source) in manifest.sources.enumerated() {
            let file = "sources/" + URL(fileURLWithPath: source.file).lastPathComponent
            try copy(AuthoringVisuals.safeURL(source.file, under: job), to: AuthoringVisuals.safeURL(file, under: stage))
            if ["md", "markdown"].contains(source.kind) {
                let resolvedName = "resolved-" + URL(fileURLWithPath: source.file).lastPathComponent
                let resolved = try AuthoringVisuals.safeURL("input/" + resolvedName, under: job)
                if fm.fileExists(atPath: resolved.path) { try copy(resolved, to: AuthoringVisuals.safeURL("sources/" + resolvedName, under: stage)) }
            }
            sources.append(["id": "source-\(i + 1)", "title": source.originalName, "kind": source.kind == "pdf" ? "pdf" : ["md", "markdown", "txt"].contains(source.kind) ? "text" : "reference", "file": file])
        }
        try copy(tutorial, to: AuthoringVisuals.safeURL("sources/tutorial.md", under: stage))
        let review = try AuthoringVisuals.safeURL("draft/review.md", under: job)
        if fm.fileExists(atPath: review.path) { try copy(review, to: AuthoringVisuals.safeURL("sources/teaching-review.md", under: stage)) }
        sources.append(["id": "frozen-tutorial", "title": "審閱後完整教程", "kind": "text", "file": "sources/tutorial.md"])
        var seenTopics = Set<String>()
        for var topic in topics {
            try Task.checkCancellation()
            let tid = try identifier(topic["id"])
            guard seenTopics.insert(tid).inserted, let blocks = topic["blocks"] as? [[String: Any]], !blocks.isEmpty, blocks.count <= 300 else { throw AuthoringFailure("主題重複，或區塊數不在1–300：\(tid)") }
            var built: [[String: Any]] = [], seenBlocks = Set<String>()
            for var block in blocks {
                try Task.checkCancellation()
                let bid = try identifier(block["id"]), type = block["type"] as? String ?? ""
                guard seenBlocks.insert(bid).inserted else { throw AuthoringFailure("區塊 ID 重複：\(tid)/\(bid)") }
                let range = block.removeValue(forKey: "tutorialLines") as? [Int]
                if let range {
                    guard range.count == 2, range[0] > 0, range[1] >= range[0], range[1] <= lines.count,
                          !(type == "markdown" && block["visibility"] as? String == "contextOnly") else { throw AuthoringFailure("教程行範圍無效或指向隱藏區塊：\(tid)/\(bid)") }
                    segments.append(["startLine": range[0], "endLine": range[1], "topicId": tid, "blockIds": [bid]])
                } else if blocks.first(where: { ($0["id"] as? String) == bid })?["tutorialLines"] != nil { throw AuthoringFailure("tutorialLines 必須是兩個整數：\(bid)") }
                let contentFile = block.removeValue(forKey: "contentFile") as? String
                if type == "markdown" {
                    let inline = block.removeValue(forKey: "text") as? String
                    guard !(range != nil && (inline != nil || contentFile != nil)), !(inline != nil && contentFile != nil) else { throw AuthoringFailure("Markdown 只能選 tutorialLines、text 或 contentFile 一種來源：\(bid)") }
                    let text: String
                    if let range { text = lines[(range[0] - 1)...(range[1] - 1)].joined(separator: "\n") }
                    else if let inline { text = inline }
                    else if let contentFile {
                        guard contentFile.lowercased().hasSuffix(".md") else { throw AuthoringFailure("Markdown 來源需為 MD：\(bid)") }
                        text = try String(contentsOf: AuthoringVisuals.safeURL(contentFile, under: job), encoding: .utf8)
                    } else { throw AuthoringFailure("Markdown 缺少內容：\(bid)") }
                    let file = "topics/\(tid)/\(bid).md"
                    let output = try AuthoringVisuals.safeURL(file, under: stage)
                    try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try text.write(to: output, atomically: true, encoding: .utf8); block["file"] = file
                }
                if type == "image" {
                    let sourceImage = block.removeValue(forKey: "sourceImage") as? String
                    let crop = block.removeValue(forKey: "crop")
                    let detailIDs = block.removeValue(forKey: "detailBlockIds") as? [String] ?? []
                    let teachingIDs = block.removeValue(forKey: "teachingBlockIds") as? [String] ?? []
                    var entry: [String: Any] = ["topicId": tid, "imageBlockId": bid, "detailBlockIds": detailIDs, "teachingBlockIds": teachingIDs]
                    if let sourceImage {
                        guard contentFile == nil, let index = manifest.sources.firstIndex(where: { $0.pages.contains { $0.image == sourceImage } }),
                              let page = manifest.sources[index].pages.first(where: { $0.image == sourceImage }) else { throw AuthoringFailure("圖片來源未列於教材清單：\(bid)") }
                        entry["sourceImage"] = sourceImage
                        let file = block["file"] as? String ?? "assets/\(tid)-\(bid)." + (crop == nil ? URL(fileURLWithPath: sourceImage).pathExtension : "png")
                        guard file.hasPrefix("assets/") else { throw AuthoringFailure("圖片須放 assets/：\(bid)") }
                        block["file"] = file
                        if let crop { _ = try AuthoringVisuals.region(crop); entry["crop"] = crop }
                        else { try copy(AuthoringVisuals.safeURL(sourceImage, under: job), to: AuthoringVisuals.safeURL(file, under: stage)) }
                        var refs = block["references"] as? [[String: Any]] ?? []
                        refs.append(["sourceId": "source-\(index + 1)", "locator": ["kind": "pdfPage", "value": page.page]])
                        block["references"] = refs
                    } else if let contentFile {
                        let ext = URL(fileURLWithPath: contentFile).pathExtension.lowercased()
                        guard ["png", "jpg", "jpeg", "webp"].contains(ext) else { throw AuthoringFailure("作者圖檔類型無效：\(bid)") }
                        let file = "assets/\(tid)-\(bid).\(ext)"; block["file"] = file
                        try copy(AuthoringVisuals.safeURL(contentFile, under: job), to: AuthoringVisuals.safeURL(file, under: stage))
                    } else { throw AuthoringFailure("圖片需要 sourceImage 或 contentFile：\(bid)") }
                    if block["display"] == nil { block["display"] = ["widthPercent": crop == nil ? 100 : 60, "maxHeight": crop == nil ? 360 : 260, "align": "center"] }
                    images.append(entry)
                } else if type != "markdown" && contentFile != nil { throw AuthoringFailure("此元件不接受 contentFile：\(bid)") }
                built.append(block)
            }
            topic["blocks"] = built
            let file = "topics/\(tid).json"; try save(topic, AuthoringVisuals.safeURL(file, under: stage))
            indexes.append(["id": tid, "file": file])
        }
        course["schemaVersion"] = "1.1"; course["courseId"] = courseID; course["contentVersion"] = "1.0.0"
        course["sources"] = sources + (course["sources"] as? [[String: Any]] ?? [])
        course["topics"] = indexes
        try save(course, stage.appendingPathComponent("course.json"))
        try save(["tutorialSha256": AuthoringMaterials.hash(tutorial), "segments": segments], stage.appendingPathComponent("TEACHING_COVERAGE.json"))
        try save(["images": images], stage.appendingPathComponent("IMAGE_MAP.json"))
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: stage, to: dest)
        try digest.write(to: checkpoint, atomically: true, encoding: .utf8)
        return true
    }

    static func report(job: URL, result: AuthoringValidationResult) throws {
        let root = try AuthoringVisuals.safeURL("course", under: job), fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        let map = try? object(AuthoringVisuals.safeURL("IMAGE_MAP.json", under: root))
        var text = "# App 原生驗證結果\n\n格式與上下文驗證：\(result.valid ? "通過" : "未通過")\n\n"
        for key in result.checks.keys.sorted() { text += "- \(key)：\(result.checks[key] == true ? "通過" : "未通過")\n" }
        text += "\n## 圖片與隱藏詳述對照\n\n"
        let course = try? object(AuthoringVisuals.safeURL("course.json", under: root))
        for entry in map?["images"] as? [[String: Any]] ?? [] {
            let tid = entry["topicId"] as? String ?? "?", bid = entry["imageBlockId"] as? String ?? "?"
            var blocks: [[String: Any]] = []
            if let ref = (course?["topics"] as? [[String: Any]])?.first(where: { $0["id"] as? String == tid }), let file = ref["file"] as? String {
                blocks = (try? object(AuthoringVisuals.safeURL(file, under: root))["blocks"] as? [[String: Any]]) ?? []
            }
            let imageFile = blocks.first { $0["id"] as? String == bid }?["file"] as? String ?? "?"
            let ids = Set(entry["detailBlockIds"] as? [String] ?? [])
            let files = blocks.filter { ids.contains($0["id"] as? String ?? "") }.compactMap { $0["file"] as? String }
            text += "- \(tid)/\(bid)（\(imageFile)）→ 詳述 \(files.joined(separator: ", "))；來源 \(entry["sourceImage"] ?? "作者圖")。標記逐項辨識與待核對內容見該 MD；本項通過代表全文進入 Q&A，不代表原生程式已判斷圖意正確。\n"
        }
        text += "\n## 限制\n\n" + (result.errors + result.limitations).map { "- " + $0 }.joined(separator: "\n")
        text += "\n\n## 檔案清單\n\n"
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            var names: [String] = []
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { names.append(String(file.path.dropFirst(root.path.count + 1))) }
            if !names.contains("NATIVE_VALIDATION.md") { names.append("NATIVE_VALIDATION.md") }
            text += names.sorted().map { "- " + $0 }.joined(separator: "\n")
        }
        try text.write(to: AuthoringVisuals.safeURL("NATIVE_VALIDATION.md", under: root), atomically: true, encoding: .utf8)
    }
}

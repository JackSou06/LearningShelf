import Foundation

struct AuthoringValidationResult: Codable {
    var valid: Bool
    var errors: [String]
    var checks: [String: Bool]
    var imageCount: Int
    var hiddenDetails: Int
    var limitations: [String]
}

enum AuthoringValidation {
    static func inspect(job: URL, prepared: PreparedCoursePackage, loader: CourseLoader,
                        courseID: String, manifest: AuthoringInputManifest) throws -> AuthoringValidationResult {
        let course = try loader.load(prepared.courseRoot), root = prepared.courseRoot
        var errors: [String] = [], checks: [String: Bool] = [:]
        func require(_ passed: Bool, _ key: String, _ message: String) {
            checks[key] = passed; if !passed { errors.append(message) }
        }
        require(course.id == courseID && course.version == "1.0.0", "reservedIdentity", "courseId／contentVersion 必須使用工作指定的新課程識別與1.0.0，不得覆蓋其他課程。")
        require(course.model["schemaVersion"] as? String == "1.1", "format11", "課程格式必須是1.1。")
        let tutorial = job.appendingPathComponent("draft/tutorial.md")
        let text = try String(contentsOf: tutorial, encoding: .utf8)
        require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "tutorialNonempty", "純教程為空白。")
        let copy = root.appendingPathComponent("sources/tutorial.md")
        require((try? AuthoringMaterials.hash(copy)) == (try? AuthoringMaterials.hash(tutorial)), "frozenTutorialPreserved", "sources/tutorial.md 必須逐位元保留 draft/tutorial.md。")
        require(!((try? String(contentsOf: job.appendingPathComponent("draft/review.md"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "teachingReviewPresent", "缺少具體教學審閱 draft/review.md。")
        var sourcePreserved = true
        for source in manifest.sources {
            let dest = root.appendingPathComponent("sources/" + URL(fileURLWithPath: source.file).lastPathComponent)
            if (try? AuthoringMaterials.hash(dest)) != source.sha256 { sourcePreserved = false; errors.append("未逐位元保留來源：\(source.originalName)") }
        }
        checks["originalSourcesPreserved"] = sourcePreserved
        let topics = course.model["topics"] as? [[String: Any]] ?? []
        let byID = Dictionary(uniqueKeysWithValues: topics.compactMap { t -> (String, [String: Any])? in (t["id"] as? String).map { ($0, t) } })
        let lines = text.components(separatedBy: "\n")
        let coverageURL = root.appendingPathComponent("TEACHING_COVERAGE.json")
        let coverage = (try? JSONSerialization.jsonObject(with: Data(contentsOf: coverageURL))) as? [String: Any] ?? [:]
        require(coverage["tutorialSha256"] as? String == (try? AuthoringMaterials.hash(tutorial)), "coverageTutorialHash", "TEACHING_COVERAGE.json 的 tutorialSha256 不符定稿。")
        var covered = Set<Int>(), mappingValid = true
        let segments = coverage["segments"] as? [[String: Any]] ?? []
        for segment in segments {
            guard let start = segment["startLine"] as? Int, let end = segment["endLine"] as? Int,
                  start > 0, end >= start, end <= lines.count,
                  let id = segment["topicId"] as? String, let topic = byID[id],
                  let ids = segment["blockIds"] as? [String], !ids.isEmpty else { mappingValid = false; continue }
            let blocks = topic["blocks"] as? [[String: Any]] ?? []
            let visible = blocks.filter { !($0["type"] as? String == "markdown" && $0["visibility"] as? String == "contextOnly") }
            guard ids.allSatisfy({ id in visible.contains { $0["id"] as? String == id } }) else { mappingValid = false; continue }
            covered.formUnion(start...end)
        }
        require(mappingValid && !segments.isEmpty, "visibleCoverageReferences", "教程覆蓋對照必須引用存在的可見區塊。")
        let missing = lines.enumerated().filter { !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !covered.contains($0.offset + 1) }.map { $0.offset + 1 }
        require(missing.isEmpty, "allTeachingLinesMapped", "仍有未映射到可見教學的教程行：\(missing.prefix(30).map(String.init).joined(separator: ","))")
        let map = (try? JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("IMAGE_MAP.json")))) as? [String: Any] ?? [:]
        require(map["images"] is [[String: Any]], "imageMapPresent", "缺少有效的IMAGE_MAP.json。")
        let images = map["images"] as? [[String: Any]] ?? []
        var mappedImages = Set<String>(), mappedSourceImages = Set<String>(), details = 0, imagesValid = true
        for entry in images {
            guard let topicID = entry["topicId"] as? String, let topic = byID[topicID],
                  let imageID = entry["imageBlockId"] as? String,
                  let blocks = topic["blocks"] as? [[String: Any]],
                  let image = blocks.first(where: { $0["id"] as? String == imageID && $0["type"] as? String == "image" }),
                  let ids = entry["detailBlockIds"] as? [String], !ids.isEmpty else { imagesValid = false; continue }
            let key = topicID + ":" + imageID
            if !mappedImages.insert(key).inserted { imagesValid = false }
            let context = loader.context.objectForKeyedSubscript("CourseCore")?.forProperty("context")?.call(withArguments: [course.model, topic, ["notes": [:], "qa": []]])?.toString() ?? ""
            for id in ids {
                guard let b = blocks.first(where: { $0["id"] as? String == id && $0["type"] as? String == "markdown" && $0["visibility"] as? String == "contextOnly" }),
                      let md = b["text"] as? String, !md.isEmpty, context.contains(md) else { imagesValid = false; continue }
                details += 1
            }
            if let sourceImage = entry["sourceImage"] as? String {
                let expected = manifest.sources.flatMap(\.pages).first { $0.image == sourceImage }
                if let expected, let file = image["file"] as? String, (try? AuthoringMaterials.hash(root.appendingPathComponent(file))) == expected.sha256 {
                    mappedSourceImages.insert(sourceImage)
                } else { imagesValid = false }
            }
        }
        var count = 0
        for topic in topics {
            for block in topic["blocks"] as? [[String: Any]] ?? [] where block["type"] as? String == "image" {
                count += 1
                if !mappedImages.contains((topic["id"] as? String ?? "") + ":" + (block["id"] as? String ?? "")) { imagesValid = false }
            }
        }
        require(imagesValid && images.count == count, "allImagesHaveHiddenQAContext", "每張課程圖片須在IMAGE_MAP.json對應本主題的隱藏詳述，且全文確實進入Q&A；不能重複或漏列圖片。")
        let expected = Set(manifest.sources.flatMap(\.pages).map(\.image))
        require(expected.isSubset(of: mappedSourceImages), "allSourcePagesPreserved", "有原投影片／圖片未完整保留，或圖檔與來源不一致：\(expected.subtracting(mappedSourceImages).sorted().prefix(20).joined(separator: ","))")
        let fm = FileManager.default
        let allowed: Set<String> = ["json", "md", "png", "jpg", "jpeg", "webp", "pdf", "pptx", "txt"]
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            var safe = true
            for case let file as URL in files {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && !allowed.contains(file.pathExtension.lowercased()) { safe = false }
            }
            require(safe, "contentFilesOnly", "課程目錄不得包含App、腳本、執行檔或不支援的檔案。")
        }
        return AuthoringValidationResult(valid: errors.isEmpty, errors: errors, checks: checks, imageCount: count,
            hiddenDetails: details, limitations: manifest.limitations + ["原生驗證確認結構、檔案、覆蓋引用及Q&A全文；不能單憑這些檢查證明圖像辨識完全正確或真實學習效果。", "未自動呼叫遠端Q&A來測試回答品質。"])
    }
}

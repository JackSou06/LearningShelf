import Foundation
import AppKit

@MainActor final class InlineVisualCodex: CodexAuthoringService {
    var onProgress: ((String) -> Void)?
    var onLoginCompleted: ((Bool) -> Void)?
    let base = FixtureCodex()
    var visualReviews = 0
    func connect(executable: URL) async throws {}
    func accountReady() async throws -> Bool { true }
    func models() async throws -> [AuthoringModel] { [AuthoringModel(id: "visual-fixture", title: "Visual fixture", effort: nil)] }
    func login() async throws -> URL { URL(string: "https://chatgpt.com/")! }
    func startThread(directory: URL, resume: String?) async throws -> String { "visual-fixture" }
    func stop() {}
    func run(thread: String, prompt: String, directory: URL, model: AuthoringModel) async throws {
        if prompt.contains("最終裁圖視覺核對") {
            let result = try AuthoringMaterials.read(AuthoringVisuals.Result.self, from: directory.appendingPathComponent("CROP_PREVIEWS.json"))
            precondition(result.crops.count == 1)
            let file = directory.appendingPathComponent("course/" + result.crops[0].file)
            precondition(NSImage(contentsOf: file) != nil, "App must render before requesting final image review")
            visualReviews += 1; return
        }
        if prompt.contains("現在只完成") || prompt.contains("內部第二階段") {
            try await base.run(thread: thread, prompt: prompt, directory: directory, model: model); return
        }
        try base.makeCourse(directory, valid: true)
        let root = directory.appendingPathComponent("course"), fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let manifest = try AuthoringMaterials.read(AuthoringInputManifest.self, from: directory.appendingPathComponent("input/sources.json"))
        let pages = manifest.sources.flatMap(\.pages); precondition(pages.count == 2)
        let courseFile = root.appendingPathComponent("course.json")
        var course = try JSONSerialization.jsonObject(with: Data(contentsOf: courseFile)) as! [String: Any]
        course["sources"] = [["id": "original-pdf", "title": "原始測試PDF", "kind": "pdf", "file": "sources/source-001.pdf"]]
        try JSONSerialization.data(withJSONObject: course).write(to: courseFile)
        var blocks: [[String: Any]] = [], entries: [[String: Any]] = []
        for (index, page) in pages.enumerated() {
            let imageID = "original-\(index)", teachingID = index == 0 ? "body" : "page-two-reading", detailID = "original-detail-\(index)"
            let file = "assets/original-\(index).jpg", detail = "topics/\(detailID).md"
            try? fm.removeItem(at: root.appendingPathComponent(file))
            try fm.copyItem(at: directory.appendingPathComponent(page.image), to: root.appendingPathComponent(file))
            try "原頁\(index + 1)：白底、SUMMATION標題、下方公式、左綠色矩形、右紅色空心橢圓；橢圓內空白，標記意圖不明。".write(to: root.appendingPathComponent(detail), atomically: true, encoding: .utf8)
            blocks.append(["id": imageID, "type": "image", "file": file, "alt": "原頁\(index + 1)", "description": "求和公式來源頁，供本段解釋對照。"])
            if index == 1 { try "本頁保留原始公式與圖形，圖形無數量標籤。".write(to: root.appendingPathComponent("topics/page-two.md"), atomically: true, encoding: .utf8) }
            blocks.append(["id": teachingID, "type": "markdown", "file": index == 0 ? "topics/body.md" : "topics/page-two.md"])
            blocks.append(["id": detailID, "type": "markdown", "file": detail, "visibility": "contextOnly"])
            entries.append(["topicId": "topic", "imageBlockId": imageID, "detailBlockIds": [detailID], "teachingBlockIds": [teachingID], "sourceImage": page.image])
        }
        let crop = ["x": 0.06, "y": 0.24, "width": 0.32, "height": 0.39]
        blocks += [["id": "green-crop", "type": "image", "file": "assets/green-crop.png", "alt": "原頁一的綠色矩形", "description": "PDF第1頁中段偏左局部，保留矩形及四周空白。", "references": [["sourceId": "original-pdf", "locator": ["kind": "pdfPage", "value": 1]]]],
                   ["id": "crop-reading", "type": "markdown", "file": "topics/crop-reading.md"],
                   ["id": "crop-detail", "type": "markdown", "file": "topics/crop-detail.md", "visibility": "contextOnly"]]
        entries.append(["topicId": "topic", "imageBlockId": "green-crop", "detailBlockIds": ["crop-detail"], "teachingBlockIds": ["crop-reading"], "sourceImage": pages[0].image, "crop": crop])
        try "上圖綠色矩形沒有尺寸或數字，不能只憑它推出面積證明。".write(to: root.appendingPathComponent("topics/crop-reading.md"), atomically: true, encoding: .utf8)
        try "PDF實際第1頁，左上比例座標x=0.06、y=0.24、寬0.32、高0.39。最終裁圖只見綠色實心矩形及白色留邊；原頁的標題、公式與紅色橢圓在裁圖外，不能描述成裁圖可見。沒有文字、圖例或可辨識的手寫記號；圖形含義未知。".write(to: root.appendingPathComponent("topics/crop-detail.md"), atomically: true, encoding: .utf8)
        for (file, value) in [("topics/topic.json", ["id": "topic", "title": "圖文就近對照", "blocks": blocks] as [String: Any]), ("IMAGE_MAP.json", ["images": entries])] {
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: root.appendingPathComponent(file))
        }
        // Deliberately leave the crop PNG absent: native rendering must materialize it.
    }
}

@main struct InlineVisualChecks {
    @MainActor static func main() async throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2]), source = URL(fileURLWithPath: CommandLine.arguments[3])
        let fm = FileManager.default; try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let temp = fm.temporaryDirectory.appendingPathComponent("learning-inline-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("courses","Courses"),("protocol","Protocol")] { try fm.createSymbolicLink(at: resources.appendingPathComponent(b), withDestinationURL: repo.appendingPathComponent(a)) }
        let defaults = UserDefaults(suiteName: "inline-" + UUID().uuidString)!; defaults.set("/usr/bin/true", forKey: "authoring.codexPath")
        let store = AppStore(resources: resources, dataDirectory: temp.appendingPathComponent("library"), transport: { _, _ in return {} })
        let service = InlineVisualCodex(), author = CourseAuthoringStore(resources: resources, dataDirectory: temp.appendingPathComponent("jobs"), defaults: defaults, service: service)
        defer { author.shutdown() }
        author.setImporter { zip, folder in try await store.importGeneratedCourse(zip, destination: folder) }
        author.create([source], destination: nil)
        for _ in 0..<1600 { if !author.isBusy { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        guard let job = author.jobs.first else { fatalError("Missing job") }
        precondition(job.stage == "completed", job.error ?? job.stage)
        precondition(service.visualReviews == 1 && store.entries.contains { $0.id == job.courseID })
        let work = author.workDirectory(job.id), course = work.appendingPathComponent("course")
        let manifest = try AuthoringMaterials.read(AuthoringInputManifest.self, from: work.appendingPathComponent("input/sources.json"))
        let report = try AuthoringMaterials.read(AuthoringValidationResult.self, from: work.appendingPathComponent("validation.json"))
        precondition(report.valid && report.imageCount == 3 && report.hiddenDetails == 3)
        precondition(report.checks["allCropsMatchSourceRegions"] == true && report.checks["imagesAdjacentToTeaching"] == true)
        let png = course.appendingPathComponent("assets/green-crop.png"), original = try Data(contentsOf: png), bitmap = NSBitmapImageRep(data: original)!
        precondition(bitmap.pixelsWide > 1000 && bitmap.pixelsHigh > 700, "Crop must use higher-resolution original PDF")
        let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        let corner = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        precondition(center.greenComponent > center.redComponent && center.greenComponent > center.blueComponent && corner.redComponent > 0.9)
        let library = try CourseLibrary(dataDirectory: temp.appendingPathComponent("validation")), loader = try CourseLoader(webRoot: repo.appendingPathComponent("web"))
        func inspect() throws -> AuthoringValidationResult { let p = try library.prepare(course); defer { p.discard() }; return try AuthoringValidation.inspect(job: work, prepared: p, loader: loader, courseID: job.courseID, manifest: manifest) }
        // A valid PNG with changed pixels must fail provenance verification.
        bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        try bitmap.representation(using: .png, properties: [:])!.write(to: png)
        let changedPixels = try inspect(); precondition(changedPixels.checks["allCropsMatchSourceRegions"] == false)
        try original.write(to: png)
        let topicFile = course.appendingPathComponent("topics/topic.json"), saved = try Data(contentsOf: topicFile)
        var topic = try JSONSerialization.jsonObject(with: saved) as! [String: Any], blocks = topic["blocks"] as! [[String: Any]]
        let moved = blocks.remove(at: 6); blocks.insert(moved, at: 0); topic["blocks"] = blocks
        try JSONSerialization.data(withJSONObject: topic).write(to: topicFile)
        let distantImage = try inspect(); precondition(distantImage.checks["imagesAdjacentToTeaching"] == false)
        try saved.write(to: topicFile)
        var withoutLocator = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        var missingReferenceBlocks = withoutLocator["blocks"] as! [[String: Any]]
        missingReferenceBlocks[6].removeValue(forKey: "references"); withoutLocator["blocks"] = missingReferenceBlocks
        try JSONSerialization.data(withJSONObject: withoutLocator).write(to: topicFile)
        let missingReference = try inspect(); precondition(missingReference.checks["cropsHaveOriginalLocators"] == false)
        try saved.write(to: topicFile)
        for value in [["x": -0.1, "y": 0.0, "width": 0.2, "height": 0.2], ["x": 0.9, "y": 0.0, "width": 0.2, "height": 0.2], ["x": 0.0, "y": 0.0, "width": 0.0, "height": 0.2]] {
            do { _ = try AuthoringVisuals.region(value); fatalError("Accepted invalid crop") } catch {}
        }
        let outside = temp.appendingPathComponent("outside"); try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: course.appendingPathComponent("assets/escape"), withDestinationURL: outside)
        do { _ = try AuthoringVisuals.safeURL("assets/escape/not-allowed.png", under: course); fatalError("Accepted linked crop output") } catch {}
        try fm.removeItem(at: course.appendingPathComponent("assets/escape"))
        try fm.copyItem(at: course, to: out.appendingPathComponent("course"))
        try original.write(to: out.appendingPathComponent("green-crop.png"))
        try AuthoringMaterials.write(report, to: out.appendingPathComponent("validation.json"))
        print("Inline visuals passed: native high-resolution PDF crop, top-left geometry/colors, final-image review before auto-import, full-page preservation, hidden Q&A context, changed-pixel rejection, distant-image rejection, invalid coordinates and linked-path rejection. Fixture Codex only.")
    }
}

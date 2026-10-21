import Foundation
import AppKit
import PDFKit
import ImageIO

/// Coordinates use the displayed page: normalized top-left x/y, width and height.
/// Crops are rendered by the App from retained inputs, never redrawn by the model.
enum AuthoringVisuals {
    struct Preview: Codable, Sendable {
        let topicId: String
        let imageBlockId: String
        let file: String
        let sourceImage: String
        let sourceName: String
        let page: Int
        let crop: [String: Double]
        let width: Int
        let height: Int
        let sha256: String
    }
    struct Result: Codable, Sendable {
        let crops: [Preview]
        var fingerprint: String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return AuthoringMaterials.hash((try? encoder.encode(crops)) ?? Data())
        }
    }
    static func safeURL(_ path: String, under root: URL) throws -> URL {
        guard CourseLoader.safePath(path) else { throw AuthoringFailure("裁圖路徑不安全：\(path)") }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let file = base.appendingPathComponent(path).standardizedFileURL
        var component = base
        for part in path.split(separator: "/") {
            component.appendPathComponent(String(part))
            if (try? component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw AuthoringFailure("裁圖路徑包含符號連結：\(path)")
            }
        }
        guard file.path.hasPrefix(base.path + "/"), file.resolvingSymlinksInPath().path == file.path else {
            throw AuthoringFailure("裁圖路徑包含連結或超出工作目錄：\(path)")
        }
        return file
    }
    static func region(_ value: Any?) throws -> [String: Double] {
        guard let raw = value as? [String: Any], raw.count == 4 else { throw AuthoringFailure("crop 必須有 x、y、width、height 四個比例座標。") }
        var r: [String: Double] = [:]
        for key in ["x", "y", "width", "height"] {
            guard let number = raw[key] as? Double, number.isFinite else { throw AuthoringFailure("crop 座標必須是有限數值。") }
            r[key] = number
        }
        guard r["x"]! >= 0, r["y"]! >= 0, r["width"]! > 0, r["height"]! > 0,
              r["x"]! + r["width"]! <= 1, r["y"]! + r["height"]! <= 1 else {
            throw AuthoringFailure("crop 必須完全位於來源頁內，不能自動截斷越界座標。")
        }
        return r
    }
    private static func parent(_ sourceImage: String, job: URL, manifest: AuthoringInputManifest) throws -> (CGImage, AuthoringSource, AuthoringPage) {
        guard let source = manifest.sources.first(where: { $0.pages.contains { $0.image == sourceImage } }),
              let page = source.pages.first(where: { $0.image == sourceImage }) else { throw AuthoringFailure("裁圖來源不在本次教材清單：\(sourceImage)") }
        let preview = try safeURL(sourceImage, under: job)
        guard try AuthoringMaterials.hash(preview) == page.sha256 else { throw AuthoringFailure("裁圖來源頁已變更，請重試恢復原件。") }
        let original = try safeURL(source.file, under: job)
        guard try AuthoringMaterials.hash(original) == source.sha256 else { throw AuthoringFailure("裁圖的原始教材已變更。") }
        let image: CGImage
        if ["pdf", "pptx"].contains(source.kind) {
            let pdf = source.kind == "pdf" ? original : try safeURL("input/converted/" + original.deletingPathExtension().lastPathComponent + ".pdf", under: job)
            if source.kind == "pptx", try AuthoringMaterials.hash(pdf) != source.renderedPDFSHA256 { throw AuthoringFailure("PPTX 轉換的原頁已變更，不能作為裁圖來源。") }
            guard let document = PDFDocument(url: pdf), let p = document.page(at: page.page - 1) else { throw AuthoringFailure("無法讀取裁圖的 PDF 原頁。") }
            let bounds = p.bounds(for: .mediaBox), scale = 3840 / max(bounds.width, bounds.height)
            let thumbnail = p.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let cg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw AuthoringFailure("無法高解析度渲染裁圖原頁。") }
            image = cg
        } else {
            guard let decoder = CGImageSourceCreateWithURL(original as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(decoder, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3840] as CFDictionary) else {
                throw AuthoringFailure("無法讀取裁圖原圖。")
            }
            image = cg
        }
        return (image, source, page)
    }
    static func render(_ entry: [String: Any], job: URL, manifest: AuthoringInputManifest) throws -> (Data, Preview) {
        let r = try region(entry["crop"])
        guard let sourceImage = entry["sourceImage"] as? String, let file = entry["file"] as? String,
              let topicID = entry["topicId"] as? String, let blockID = entry["imageBlockId"] as? String else {
            throw AuthoringFailure("裁圖缺少來源或對應區塊。")
        }
        let (image, source, page) = try parent(sourceImage, job: job, manifest: manifest)
        let rectangle = CGRect(x: floor(r["x"]! * Double(image.width)), y: floor(r["y"]! * Double(image.height)),
            width: ceil((r["x"]! + r["width"]!) * Double(image.width)) - floor(r["x"]! * Double(image.width)),
            height: ceil((r["y"]! + r["height"]!) * Double(image.height)) - floor(r["y"]! * Double(image.height)))
        guard rectangle.width >= 64, rectangle.height >= 64, let cropped = image.cropping(to: rectangle),
              let data = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
            throw AuthoringFailure("裁圖太小或無法產生；請擴大範圍保留可讀的圖例與標記。")
        }
        return (data, Preview(topicId: topicID, imageBlockId: blockID, file: file, sourceImage: sourceImage,
            sourceName: source.originalName, page: page.page, crop: r, width: cropped.width, height: cropped.height, sha256: AuthoringMaterials.hash(data)))
    }
    static func materialize(job: URL, manifest: AuthoringInputManifest) throws -> Result {
        let root = try safeURL("course", under: job)
        func json(_ path: String) throws -> [String: Any] {
            let url = try safeURL(path, under: root)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attributes.isRegularFile == true, (attributes.fileSize ?? Int.max) <= 20_000_000 else { throw AuthoringFailure("裁圖對照／主題 JSON 超過 20 MB 或不是一般檔案。") }
            guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw AuthoringFailure("無效的裁圖對照或課程 JSON：\(path)")
            }
            return value
        }
        let map = try json("IMAGE_MAP.json"), course = try json("course.json")
        let entries = map["images"] as? [[String: Any]] ?? []
        guard entries.count <= 2000 else { throw AuthoringFailure("圖片對照超過 2000 張，請分開製作。") }
        var topics: [String: [String: Any]] = [:], fileUses: [String: Int] = [:]
        for ref in course["topics"] as? [[String: Any]] ?? [] {
            guard let id = ref["id"] as? String, let file = ref["file"] as? String, topics[id] == nil else { throw AuthoringFailure("裁圖對應的主題識別無效或重複。") }
            let topic = try json(file); topics[id] = topic
            for block in topic["blocks"] as? [[String: Any]] ?? [] where block["type"] as? String == "image" {
                if let file = block["file"] as? String { fileUses[file, default: 0] += 1 }
            }
        }
        var crops: [Preview] = [], bytes = 0
        for var entry in entries where entry["crop"] != nil {
            try Task.checkCancellation()
            guard let topicID = entry["topicId"] as? String, let imageID = entry["imageBlockId"] as? String,
                  let blocks = topics[topicID]?["blocks"] as? [[String: Any]],
                  let block = blocks.first(where: { $0["id"] as? String == imageID && $0["type"] as? String == "image" }),
                  let file = block["file"] as? String, file.hasPrefix("assets/"), file.hasSuffix(".png"), fileUses[file] == 1 else {
                throw AuthoringFailure("每張裁圖須對應存在的 image 區塊，使用唯一的 assets/*.png，不能覆寫原圖或共用輸出。")
            }
            let target = try safeURL(file, under: root)
            entry["file"] = file
            let (data, preview) = try render(entry, job: job, manifest: manifest)
            bytes += data.count
            guard bytes <= CourseLoader.maximumContentBytes else { throw AuthoringFailure("本次裁圖合計超過閱讀器 100 MB 載入限制；請調整配圖或分開製作，不能刪去教學規避限制。") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: try safeURL(file, under: root), options: .atomic)
            crops.append(preview)
        }
        let result = Result(crops: crops)
        try AuthoringMaterials.write(result, to: safeURL("CROP_PREVIEWS.json", under: job))
        return result
    }
}

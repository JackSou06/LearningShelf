import Foundation
import AppKit
import PDFKit
import CryptoKit

struct AuthoringSource: Codable {
    var file: String
    var originalName: String
    var kind: String
    var sha256: String
    var pages: [AuthoringPage]
    var renderedPDFSHA256: String? = nil
}
struct AuthoringPage: Codable {
    var image: String
    var page: Int
    var sha256: String
}
struct AuthoringInputManifest: Codable {
    var sources: [AuthoringSource]
    var limitations: [String]
}

/// Processes used for file conversion are cancellable independently of Codex.
final class AuthoringProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let p = process; lock.unlock()
        if p?.isRunning == true { p?.terminate() }
        if let p { DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } }
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, log: URL, failureMessage: String = "檔案處理未完成，請查看工作資料夾的處理紀錄。") throws {
        try Task.checkCancellation()
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments; p.currentDirectoryURL = cwd
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        p.standardOutput = handle; p.standardError = handle
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = p
        do { try p.run() } catch { process = nil; lock.unlock(); throw error }
        lock.unlock()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: timeout)
        p.waitUntilExit(); timeout.cancel()
        lock.lock(); process = nil; let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        guard p.terminationStatus == 0 else { throw AuthoringFailure(failureMessage) }
    }
}

enum AuthoringMaterials {
    static let extensions: Set<String> = ["pdf", "pptx", "md", "markdown", "png", "jpg", "jpeg", "webp"]
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hash(_ file: URL) throws -> String { hash(try Data(contentsOf: file, options: .mappedIfSafe)) }
    static func write<T: Encodable>(_ value: T, to file: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: file, options: .atomic)
    }
    static func read<T: Decodable>(_ type: T.Type, from file: URL) throws -> T { try JSONDecoder().decode(type, from: Data(contentsOf: file)) }

    static func copySources(_ urls: [URL], to root: URL) throws -> [AuthoringSource] {
        guard !urls.isEmpty && urls.count <= 100 else { throw AuthoringFailure("一次請提供 1–100 個教材檔案。") }
        let fm = FileManager.default, folder = root.appendingPathComponent("input")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var total = 0, result: [AuthoringSource] = []
        for (i, url) in urls.enumerated() {
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attr = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            let ext = url.pathExtension.lowercased()
            guard attr.isRegularFile == true, attr.isSymbolicLink != true, extensions.contains(ext) else { throw AuthoringFailure("不支援的教材：\(url.lastPathComponent)。請使用 PDF、PPTX、MD 或圖片。") }
            total += attr.fileSize ?? 0
            guard total <= 200_000_000 else { throw AuthoringFailure("本次教材合計超過 200 MB，請分開製作。") }
            let name = String(format: "source-%03d.", i + 1) + ext, dest = folder.appendingPathComponent(name)
            try fm.copyItem(at: url, to: dest)
            result.append(AuthoringSource(file: "input/" + name, originalName: url.lastPathComponent, kind: ext,
                                           sha256: try hash(dest), pages: []))
            // Preserve local Markdown images without granting traversal outside the selected file's directory.
            if ["md", "markdown"].contains(ext) {
                let text = try String(contentsOf: dest, encoding: .utf8)
                let regex = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^\s\)]+)(?:\s+[^\)]*)?\)"#)
                var rewritten = text
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                    guard let range = Range(match.range(at: 1), in: text) else { continue }
                    let value = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    guard CourseLoader.safePath(value), ["png", "jpg", "jpeg", "webp"].contains(URL(fileURLWithPath: value).pathExtension.lowercased()) else { continue }
                    let image = url.deletingLastPathComponent().appendingPathComponent(value)
                    let base = url.deletingLastPathComponent().resolvingSymlinksInPath().path + "/"
                    guard image.resolvingSymlinksInPath().path.hasPrefix(base), fm.fileExists(atPath: image.path) else { continue }
                    let a = try image.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard a.isRegularFile == true, a.isSymbolicLink != true else { continue }
                    total += a.fileSize ?? 0; guard total <= 200_000_000 else { throw AuthoringFailure("含 MD 圖片的教材超過 200 MB。") }
                    let imageName = "md-\(i + 1)-" + UUID().uuidString + "." + image.pathExtension.lowercased()
                    let imageDest = folder.appendingPathComponent(imageName); try fm.copyItem(at: image, to: imageDest)
                    result.append(AuthoringSource(file: "input/" + imageName, originalName: value, kind: image.pathExtension.lowercased(), sha256: try hash(imageDest), pages: []))
                    rewritten.replaceSubrange(range, with: imageName)
                }
                // The byte-identical original stays available; use this sibling for resolved local images.
                if rewritten != text { try rewritten.write(to: folder.appendingPathComponent("resolved-" + name), atomically: true, encoding: .utf8) }
            }
        }
        return result
    }

    static func prepare(root: URL, sources: [AuthoringSource], runner: AuthoringProcessRunner,
                        progress: @escaping @Sendable (String) -> Void) throws -> AuthoringInputManifest {
        let fm = FileManager.default, rendered = root.appendingPathComponent("input/rendered")
        try fm.createDirectory(at: rendered, withIntermediateDirectories: true)
        var prepared: [AuthoringSource] = [], limitations: [String] = []
        var count = 0
        for var source in sources {
            try Task.checkCancellation()
            let file = root.appendingPathComponent(source.file)
            guard try hash(file) == source.sha256 else { throw AuthoringFailure("教材在準備後已變更，請重新加入原始教材。") }
            progress("讀取 \(source.originalName)")
            var pdf = file
            if source.kind == "pptx" { pdf = try convertPresentation(file, root: root, runner: runner); source.renderedPDFSHA256 = try hash(pdf) }
            if ["pdf", "pptx"].contains(source.kind) {
                guard let document = PDFDocument(url: pdf), !document.isLocked, document.pageCount > 0 else { throw AuthoringFailure("PDF 無法開啟或需要密碼：\(source.originalName)") }
                guard document.pageCount <= 2000 else { throw AuthoringFailure("單份教材超過 2000 頁，請分開製作。") }
                source.pages = []
                var transcript = ""
                for i in 0..<document.pageCount {
                    try Task.checkCancellation()
                    try autoreleasepool {
                        guard let page = document.page(at: i) else { throw AuthoringFailure("無法讀取 PDF 第 \(i + 1) 頁。") }
                        let bounds = page.bounds(for: .mediaBox), scale = 1920 / max(bounds.width, bounds.height)
                        guard bounds.width > 0 && bounds.height > 0 else { throw AuthoringFailure("PDF 頁面尺寸無效。") }
                        let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) else { throw AuthoringFailure("無法轉出投影片圖片。") }
                        let stem = file.deletingPathExtension().lastPathComponent, name = stem + String(format: "-page-%04d.jpg", i + 1)
                        let target = rendered.appendingPathComponent(name); try jpg.write(to: target, options: .atomic)
                        source.pages.append(AuthoringPage(image: "input/rendered/" + name, page: i + 1, sha256: hash(jpg)))
                        transcript += "\n\n## PDF 實際頁序 \(i + 1)\n" + (page.string ?? "（沒有文字層；請實際看圖）")
                    }
                    progress("\(source.originalName)：已準備 \(i + 1) / \(document.pageCount) 頁")
                }
                try transcript.write(to: rendered.appendingPathComponent(file.lastPathComponent + ".txt"), atomically: true, encoding: .utf8)
                count += source.pages.count
            } else if ["png", "jpg", "jpeg", "webp"].contains(source.kind) {
                guard NSImage(contentsOf: file) != nil else { throw AuthoringFailure("無法開啟圖片：\(source.originalName)") }
                source.pages = [AuthoringPage(image: source.file, page: 1, sha256: source.sha256)]; count += 1
            } else {
                let text = try String(contentsOf: file, encoding: .utf8)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AuthoringFailure("MD 教材為空白：\(source.originalName)") }
                let resolved = file.deletingLastPathComponent().appendingPathComponent("resolved-" + file.lastPathComponent)
                let imageText = (try? String(contentsOf: resolved, encoding: .utf8)) ?? text
                let regex = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^\s\)]+)(?:\s+[^\)]*)?\)"#)
                for match in regex.matches(in: imageText, range: NSRange(imageText.startIndex..., in: imageText)) {
                    guard let range = Range(match.range(at: 1), in: imageText) else { continue }
                    let value = String(imageText[range]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    if !CourseLoader.safePath(value) || !fm.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent(value).path) {
                        limitations.append("\(source.originalName) 的圖片引用未附帶或不能安全讀取：\(value)。需在教程與報告明列未核對，不可憑檔名或網址猜內容。")
                    }
                }
                if text.contains("<img") || text.range(of: #"!\[[^\]]*\]\["#, options: .regularExpression) != nil {
                    limitations.append("\(source.originalName) 含 HTML 或參照式圖片語法，尚未自動收集該圖片；需核對附件並明列缺口。")
                }
            }
            prepared.append(source)
        }
        guard count <= 2000 else { throw AuthoringFailure("本次圖片超過 2000 張，請分開製作。") }
        let manifest = AuthoringInputManifest(sources: prepared, limitations: limitations)
        try write(manifest, to: root.appendingPathComponent("input/sources.json"))
        return manifest
    }

    private static func convertPresentation(_ file: URL, root: URL, runner: AuthoringProcessRunner) throws -> URL {
        let fm = FileManager.default, folder = root.appendingPathComponent("input/converted")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".pdf")
        let failure = "PPTX 轉換未完成。請先在 Keynote 開啟教材並完成首次設定／自動化授權，或改用 LibreOffice、先匯出 PDF 後重試；詳細原因見結果資料夾的 conversion.log。"
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        let libre = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
        if fm.isExecutableFile(atPath: libre) {
            try runner.run(libre, ["-env:UserInstallation=" + root.appendingPathComponent("lo-profile").absoluteString, "--headless", "--convert-to", "pdf", "--outdir", folder.path, file.path], cwd: root, log: root.appendingPathComponent("conversion.log"), failureMessage: failure)
        } else if fm.fileExists(atPath: "/Applications/Keynote.app") {
            // Keynote can return missing value while asynchronously importing PowerPoint.
            // Open a uniquely named copy and wait only for that new document, never a user's front document.
            let importedName = "LearningShelf-" + UUID().uuidString
            let imported = folder.appendingPathComponent(importedName + ".pptx")
            try fm.copyItem(at: file, to: imported)
            defer { try? fm.removeItem(at: imported) }
            let script = """
            on run argv
              set sourceDocument to missing value
              tell application id "com.apple.iWork.Keynote"
                activate
                set priorIDs to id of every document
                set sourceDocument to open (POSIX file (item 1 of argv))
                repeat 600 times
                  if sourceDocument is not missing value then exit repeat
                  repeat with candidate in documents
                    if (name of candidate starts with (item 3 of argv)) and (priorIDs does not contain id of candidate) then
                      set sourceDocument to candidate
                      exit repeat
                    end if
                  end repeat
                  if sourceDocument is not missing value then exit repeat
                  delay 0.2
                end repeat
                if sourceDocument is missing value then error "Keynote did not finish importing this presentation. Complete Keynote first-launch setup, check Automation permission, or use LibreOffice / export PDF and retry."
                try
                  export sourceDocument to (POSIX file (item 2 of argv)) as PDF
                on error errorMessage number errorNumber
                  close sourceDocument saving no
                  error errorMessage number errorNumber
                end try
                close sourceDocument saving no
              end tell
            end run
            """
            let path = root.appendingPathComponent("convert-presentation.applescript"); try script.write(to: path, atomically: true, encoding: .utf8)
            try runner.run("/usr/bin/osascript", [path.path, imported.path, output.path, importedName], cwd: root, log: root.appendingPathComponent("conversion.log"), failureMessage: failure)
        } else { throw AuthoringFailure("製作 PPTX 課程需要此 Mac 安裝 Keynote 或 LibreOffice，以保留每頁實際圖形；安裝後可按重試。PDF 與 MD 不需要此轉換工具。") }
        guard fm.fileExists(atPath: output.path) else { throw AuthoringFailure("PPTX 未成功轉出 PDF；請先確認 Keynote 已完成首次設定並允許自動化，或用 LibreOffice／自行匯出 PDF 後重試。") }
        return output
    }
}

import Foundation
import CArchive

struct PreparedCoursePackage: Sendable {
    let temporaryDirectory: URL
    let courseRoot: URL
    func discard() { try? FileManager.default.removeItem(at: temporaryDirectory) }
}

/// Imported content is immutable. The catalog selects a generation only after validation succeeds.
struct CourseLibrary: Sendable {
    static let maximumBytes: Int64 = 200_000_000
    static let maximumEntries = 10_000
    let directory: URL
    private var incoming: URL { directory.appendingPathComponent(".incoming", isDirectory: true) }

    init(dataDirectory: URL) throws {
        let requested = dataDirectory.appendingPathComponent("Courses", isDirectory: true)
        try FileManager.default.createDirectory(at: requested.appendingPathComponent(".incoming", isDirectory: true), withIntermediateDirectories: true)
        // Resolve the existing base once; Foundation resolves a missing child differently for /private/tmp.
        directory = requested.resolvingSymlinksInPath().standardizedFileURL
    }
    static func validID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil
    }
    func generation(_ folder: String, courseID: String) throws -> URL {
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
        guard Self.validID(courseID), parts.count == 2, parts[0] == courseID, UUID(uuidString: String(parts[1])) != nil else {
            throw CourseFailure(message: "課程庫位置無效")
        }
        let url = directory.appendingPathComponent(folder, isDirectory: true)
        guard url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") else {
            throw CourseFailure(message: "課程庫位置不安全")
        }
        return url
    }
    func content(_ folder: String, courseID: String) throws -> URL { try generation(folder, courseID: courseID).appendingPathComponent("Content", isDirectory: true) }
    func snapshot(_ folder: String, courseID: String) throws -> URL { try generation(folder, courseID: courseID).appendingPathComponent("snapshot.json") }

    func prepare(_ source: URL) throws -> PreparedCoursePackage {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let temporary = incoming.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unpacked = temporary.appendingPathComponent("Unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        do {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw CourseFailure(message: "請匯入實際的課程資料夾或 ZIP，不支援符號連結") }
            if values.isDirectory == true { try copyDirectory(source, to: unpacked) }
            else {
                guard source.pathExtension.lowercased() == "zip", values.isRegularFile == true else { throw CourseFailure(message: "請選擇課程 ZIP 或包含 course.json 的資料夾") }
                guard Int64(values.fileSize ?? 0) <= Self.maximumBytes else { throw CourseFailure(message: "課程 ZIP 超過 200 MB") }
                try extractZIP(source, to: unpacked)
            }
            let root: URL
            if FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("course.json").path) { root = unpacked }
            else {
                let children = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: [.isDirectoryKey])
                let candidates = children.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("course.json").path) }
                guard candidates.count == 1, children.count == 1 else { throw CourseFailure(message: "每個 ZIP 請只放一門課程；course.json 可放最外層或單一課程資料夾內") }
                root = candidates[0]
            }
            return PreparedCoursePackage(temporaryDirectory: temporary, courseRoot: root)
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
    private func ignored(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == "__MACOSX" || $0 == ".DS_Store" || $0.hasPrefix("._") }
    }
    private func checkedPath(_ raw: String) throws -> String {
        let path = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard CourseLoader.safePath(path), path.split(separator: "/").count <= 32 else { throw CourseFailure(message: "課程壓縮包含不安全的路徑：\(raw)") }
        return path
    }
    private func copyDirectory(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let base = source.path + "/"
        var traversalError: Error?
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in traversalError = error; return false }) else { throw CourseFailure(message: "無法讀取課程資料夾") }
        var count = 0, total: Int64 = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard canonical.path.hasPrefix(base) else { throw CourseFailure(message: "課程位置不安全") }
            let path = try checkedPath(String(canonical.path.dropFirst(base.count)))
            if ignored(path) { enumerator.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            count += 1
            guard count <= Self.maximumEntries, values.isSymbolicLink != true else { throw CourseFailure(message: "課程檔案過多或包含符號連結") }
            let destination = target.appendingPathComponent(path)
            if values.isDirectory == true { try fm.createDirectory(at: destination, withIntermediateDirectories: true) }
            else {
                guard values.isRegularFile == true else { throw CourseFailure(message: "課程只能包含一般檔案與資料夾") }
                total += Int64(values.fileSize ?? 0)
                guard total <= Self.maximumBytes else { throw CourseFailure(message: "課程解壓後超過 200 MB") }
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: destination)
                try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
            }
        }
        if let traversalError { throw traversalError }
    }
    private func extractZIP(_ source: URL, to target: URL) throws {
        guard let archive = archive_read_new() else { throw CourseFailure(message: "無法開啟 ZIP") }
        defer { archive_read_free(archive) }
        archive_read_support_format_zip_seekable(archive)
        guard archive_read_open_filename(archive, source.path, 65536) == ARCHIVE_OK else { throw CourseFailure(message: "無法讀取 ZIP，請確認檔案完整且未加密") }
        var entry: OpaquePointer?
        var total: Int64 = 0, count = 0
        var seen = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let name = archive_entry_pathname(entry), let raw = String(validatingUTF8: name) else { throw CourseFailure(message: "ZIP 損壞或檔名無法辨識，請使用 UTF-8 檔名") }
            let path = try checkedPath(raw)
            let kind = archive_entry_filetype(entry)
            guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil, kind == AE_IFREG || kind == AE_IFDIR else { throw CourseFailure(message: "ZIP 不能包含連結或特殊檔案") }
            count += 1
            guard count <= Self.maximumEntries else { throw CourseFailure(message: "ZIP 超過 10,000 個項目") }
            guard archive_entry_is_encrypted(entry) == 0 else { throw CourseFailure(message: "不支援加密的課程 ZIP") }
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else { throw CourseFailure(message: "ZIP 含重複或大小寫衝突的檔名：\(path)") }
            let declared = archive_entry_size(entry)
            guard declared >= 0, declared <= Self.maximumBytes - total else { throw CourseFailure(message: "課程解壓後超過 200 MB") }
            let omit = ignored(path)
            let destination = target.appendingPathComponent(path)
            if kind == AE_IFDIR {
                guard declared == 0 else { throw CourseFailure(message: "ZIP 資料夾項目大小無效") }
                if !omit { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
                continue
            }
            var handle: FileHandle?
            if !omit {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o644]) else { throw CourseFailure(message: "無法寫入課程檔案") }
                handle = try FileHandle(forWritingTo: destination)
            }
            defer { try? handle?.close() }
            var fileBytes: Int64 = 0
            while true {
                try Task.checkCancellation()
                let read = archive_read_data(archive, &buffer, buffer.count)
                guard read >= 0 else { throw CourseFailure(message: "ZIP 內容或校驗碼錯誤，未匯入課程") }
                if read == 0 { break }
                total += Int64(read); fileBytes += Int64(read)
                guard total <= Self.maximumBytes else { throw CourseFailure(message: "課程解壓後超過 200 MB") }
                if let handle { try handle.write(contentsOf: Data(buffer.prefix(read))) }
            }
            guard fileBytes == declared else { throw CourseFailure(message: "ZIP 檔案大小與宣告不符") }
        }
    }
    /// On failure the old generation and catalog remain untouched.
    func install(_ prepared: PreparedCoursePackage, courseID: String, commit: (String, URL) throws -> Void) throws {
        guard Self.validID(courseID) else { throw CourseFailure(message: "課程 ID 無效") }
        let folder = courseID + "/" + UUID().uuidString
        let generation = try generation(folder, courseID: courseID)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        do {
            let root = generation.appendingPathComponent("Content", isDirectory: true)
            try FileManager.default.moveItem(at: prepared.courseRoot, to: root)
            try commit(folder, root)
        } catch { try? FileManager.default.removeItem(at: generation); throw error }
    }
    func discard(_ folder: String, courseID: String) throws {
        let url = try generation(folder, courseID: courseID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let parent = url.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true { try? FileManager.default.removeItem(at: parent) }
    }
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        // Numeric string comparison avoids integer overflow for otherwise-valid long version fields.
        let left = lhs.split(separator: "."), right = rhs.split(separator: ".")
        for (a, b) in zip(left, right) {
            let result = String(a).compare(String(b), options: .numeric)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }
}

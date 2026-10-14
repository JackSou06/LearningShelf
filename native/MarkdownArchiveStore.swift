import Foundation

/// A readable derivative of SQLite records, separate from the course and API key.
final class MarkdownArchiveStore {
    let folder: URL
    let defaults: UserDefaults
    init(folder: URL, defaults: UserDefaults = .standard) { self.folder=folder;self.defaults=defaults }
    func target(_ id: String) throws -> URL {
        guard id.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$",options:.regularExpression) != nil else {throw CourseFailure(message:"課程 ID 不安全")}
        if let data=defaults.data(forKey:"markdown-target:"+id) {
            var stale=false
            let url=try URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale)
            if stale {try bind(id,to:url)}
            return url
        }
        let dir=folder.appendingPathComponent("Markdown",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir.appendingPathComponent(id+"-learning.md")
    }
    func bind(_ id: String, to url: URL) throws {
        guard url.pathExtension.lowercased()=="md" else {throw CourseFailure(message:"請選擇 .md 檔案")}
        let bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
        defaults.set(bookmark,forKey:"markdown-target:"+id)
    }
    @discardableResult func write(_ id: String, text: String) throws -> URL {
        let u=try target(id),access=u.startAccessingSecurityScopedResource()
        defer{if access{u.stopAccessingSecurityScopedResource()}}
        if (try? String(contentsOf:u,encoding:.utf8)) != text {try text.write(to:u,atomically:true,encoding:.utf8)}
        return u
    }
}

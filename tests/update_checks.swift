import Foundation

@main struct UpdateChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("learning-update-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("New.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for (source, target) in [("web", "Web"), ("courses", "Courses")] {
            try FileManager.default.createSymbolicLink(at: resources.appendingPathComponent(target), withDestinationURL: root.appendingPathComponent(source))
        }
        let data = temp.appendingPathComponent("data")
        let store = AppStore(resources: resources, dataDirectory: data)
        try store.session.setKey("fixture-key-survives-app-replacement", remember: true)
        let entry = store.entries.first { $0.id == "example-linear-algebra" }!
        assert(entry.bundledFolder == "linear-algebra")
        var legacy = entry
        legacy.bundledFolder = nil
        legacy.bookmark = nil
        legacy.path = "/gone/Old.app/Contents/Resources/Courses/linear-algebra"
        let expected = resources.appendingPathComponent("Courses/linear-algebra")
        assert(store.root(legacy) == expected, "legacy bundle locations follow the installed app")
        var external = entry
        external.bundledFolder = nil; external.bookmark = nil
        external.path = "/my/course-folder/linear-algebra"
        assert(store.root(external).path == external.path, "external courses keep their location")
        var unsafe = legacy
        unsafe.bundledFolder = "../../private"; unsafe.path = "/external/course"
        assert(store.root(unsafe).path == unsafe.path)
        var mismatch = legacy
        mismatch.id = "not-the-bundled-course"
        assert(store.root(mismatch).path == mismatch.path)
        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(CatalogEntry.self, from: encoded)
        assert(decoded.bundledFolder == nil)
        let course = try store.loader.load(expected)
        var record = try store.session.load(course)
        record["notes"] = ["vector": "更新前最後一筆筆記"]
        record["qaDrafts"] = ["vector": "尚未送出的問題"]
        _ = try store.session.save(record, base: try store.session.load(course), course: course)
        var flushed = false
        let token = UUID()
        store.readerFlushers[token] = { flushed = true }
        try await store.prepareToQuit()
        assert(flushed && store.isPreparingToQuit)
        let reopened = try RecordStore(folder: data).load(course.id)!
        let replacementResources = temp.appendingPathComponent("Replacement.app/Contents/Resources")
        try FileManager.default.createDirectory(at: replacementResources, withIntermediateDirectories: true)
        for (source, target) in [("web", "Web"), ("courses", "Courses")] {
            try FileManager.default.createSymbolicLink(at: replacementResources.appendingPathComponent(target), withDestinationURL: root.appendingPathComponent(source))
        }
        let replacement = AppStore(resources: replacementResources, dataDirectory: data)
        assert(replacement.session.activeKey == "fixture-key-survives-app-replacement", "a replacement app at another path retains the saved API key")
        try replacement.session.setKey("", remember: false)
        assert(replacement.session.activeKey == "fixture-key-survives-app-replacement", "changing settings without a key cannot erase the saved value")
        assert((reopened["notes"] as! [String: String])["vector"] == "更新前最後一筆筆記")
        assert((reopened["qaDrafts"] as! [String: String])["vector"] == "尚未送出的問題")
        let archive = try String(contentsOf: MarkdownArchiveStore(folder: data).target(course.id), encoding: .utf8)
        assert(archive.contains("更新前最後一筆筆記"), "debounced Markdown must be flushed before quit")
        do {
            _ = try store.session.save(record, base: record, course: course)
            fatalError("no writes accepted after shutdown is sealed")
        } catch {}
        await store.resumeAfterCancelledQuit()
        assert(!store.isPreparingToQuit)
        _ = try store.session.save(record, base: record, course: course)
        store.readerFlushers[token] = { throw CourseFailure(message: "simulated failed browser save") }
        do { try await store.prepareToQuit(); fatalError("failed reader save must stop termination") } catch {}
        await store.resumeAfterCancelledQuit()
        assert(!store.isPreparingToQuit)
        let blocked = try HostSession(webRoot: root.appendingPathComponent("web"), records: store.records,
            keyProvider: { "test-key" }, transport: { _, _ in return {} })
        _ = try blocked.ask(course, topicId: "vector", question: "pending question", requestId: "pending-update-test")
        assert(blocked.hasActiveRequests)
        do { try blocked.prepareToQuit(); fatalError("pending AI request must stop quit") } catch {}
        _ = try blocked.cancel(course, requestId: "pending-update-test")
        assert(!blocked.hasActiveRequests)
        try blocked.prepareToQuit()
        print("Update checks passed: legacy/relocated/external courses, drafts and SQLite reopen, MD flush, save failure recovery, pending AI request guard.")
    }
}

import Foundation

func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "") throws {
    let passed = try condition()
    assert(passed, message)
}

@main struct CourseLibraryChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2])
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("learning-library-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for (source, target) in [("web", "Web"), ("courses", "Courses")] {
            try FileManager.default.createSymbolicLink(at: resources.appendingPathComponent(target), withDestinationURL: root.appendingPathComponent(source))
        }
        let data = temp.appendingPathComponent("data")
        let store = AppStore(resources: resources, dataDirectory: data, transport: { _, _ in return {} })
        func install(_ name: String) async throws -> LoadedCourse {
            let prepared = try store.library.prepare(fixtures.appendingPathComponent(name))
            defer { prepared.discard() }
            return try await store.installPrepared(prepared, confirmReplacement: false)!
        }
        for name in ["traversal.zip", "absolute.zip", "windows.zip", "duplicate.zip", "multiple.zip", "link.zip", "oversized.zip", "corrupt.zip", "truncated.zip"] {
            do { let package = try store.library.prepare(fixtures.appendingPathComponent(name)); package.discard(); fatalError("Accepted unsafe ZIP: \(name)") }
            catch { print("Rejected:", name) }
        }
        let wrapped = try store.library.prepare(fixtures.appendingPathComponent("wrapped.zip"))
        try check(try store.loader.load(wrapped.courseRoot).id == "library-import-test")
        wrapped.discard()
        let aliasData = URL(fileURLWithPath: "/private/tmp/learning-library-alias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: aliasData) }
        let aliasLibrary = try CourseLibrary(dataDirectory: aliasData)
        let aliased = try aliasLibrary.prepare(fixtures.appendingPathComponent("course-v1"))
        defer { aliased.discard() }
        try aliasLibrary.install(aliased, courseID: "library-import-test") { _, root in
            try check(try store.loader.load(root).id == "library-import-test")
        }
        let first = try await install("root.zip")
        let entry1 = store.entries.first { $0.id == first.id }!
        try check(entry1.managedFolder != nil && first.root.path.hasPrefix(store.library.directory.path))
        let originalZIP = fixtures.appendingPathComponent("root.zip")
        let originalBytes = try Data(contentsOf: originalZIP)
        try FileManager.default.removeItem(at: originalZIP)
        try check(try store.loader.load(store.root(entry1)).id == first.id, "reading must not depend on the ZIP")
        try originalBytes.write(to: originalZIP)
        var record = try store.session.load(first)
        record["notes"] = ["vector": "既有筆記"]
        record["qaDrafts"] = ["vector": "問答草稿"]
        record["seen"] = ["vector"]
        record["answers"] = ["linear-combination:check": ["optionId": "scale-add", "version": "1.0.0"]]
        record["qa"] = [["id": "retained-question", "topic": "vector", "question": "原有問題", "answer": "原有回答", "status": "done", "version": "1.0.0", "time": "2026-10-16T00:00:00Z", "model": "test"]]
        try store.records.save(record)
        store.selected = first
        let second = try await install("updated.zip")
        let entry2 = store.entries.first { $0.id == first.id }!
        try check(entry2.version == "1.0.1" && entry2.managedFolder != entry1.managedFolder)
        try check(!FileManager.default.fileExists(atPath: first.root.path), "obsolete generation should be cleaned")
        let saved = try store.session.load(second)
        try check((saved["notes"] as! [String: String])["vector"] == "既有筆記")
        try check((saved["qaDrafts"] as! [String: String])["vector"] == "問答草稿")
        try check((saved["qa"] as! [[String: Any]]).first?["answer"] as? String == "原有回答")
        try check((saved["answers"] as! [String: [String: String]])["linear-combination:check"]?["version"] == "1.0.0")
        try check((saved["seen"] as! [String]).contains("vector"))
        do { _ = try store.session.save(record, base: record, course: first); fatalError("stale reader must not overwrite the updated course") } catch {}
        do { _ = try await install("root.zip"); fatalError("downgrade accepted") } catch {}
        do { _ = try await install("invalid.zip"); fatalError("invalid course accepted") } catch {}
        try check(store.entries.first { $0.id == first.id }?.version == "1.0.1")
        try check(FileManager.default.fileExists(atPath: second.root.path))
        // A catalog write failure must not replace the last working generation.
        let catalog = data.appendingPathComponent("catalog.json"), savedCatalog = data.appendingPathComponent("catalog.saved")
        try FileManager.default.moveItem(at: catalog, to: savedCatalog)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
        do { _ = try await install("updated.zip"); fatalError("catalog failure was ignored") } catch {}
        try FileManager.default.removeItem(at: catalog)
        try FileManager.default.moveItem(at: savedCatalog, to: catalog)
        try check(store.root(store.entries.first { $0.id == first.id }!) == second.root)
        try check(FileManager.default.fileExists(atPath: second.root.path))
        store.session.temporaryKey = "fake-library-test-key"
        _ = try store.session.ask(second, topicId: "vector", question: "測試進行中問答", requestId: "library-pending")
        try check(store.session.hasActiveRequests(for: second.id))
        do { try await store.deleteCourse(entry2, includingRecords: true); fatalError("deleted during an active request") } catch {}
        do { _ = try await install("updated.zip"); fatalError("updated during an active request") } catch {}
        _ = try store.session.cancel(second, requestId: "library-pending")
        try await store.deleteCourse(entry2, includingRecords: false)
        try check(!store.entries.contains { $0.id == first.id })
        try check(!FileManager.default.fileExists(atPath: second.root.path))
        try check(try store.records.load(first.id) != nil)
        do { _ = try store.session.load(second); fatalError("deleted reader resurrected records") } catch {}
        let restored = try await install("updated.zip")
        try check((try store.session.load(restored)["notes"] as! [String: String])["vector"] == "既有筆記")
        do { _ = try store.session.save(record, base: record, course: second); fatalError("old reader accepted after reimport") } catch {}
        let restoredEntry = store.entries.first { $0.id == restored.id }!
        _ = try store.session.syncMarkdown(restored)
        try await store.deleteCourse(restoredEntry, includingRecords: true)
        try check(try store.records.load(restored.id) == nil)
        try check(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Markdown/" + restored.id + "-learning.md").path))
        try check(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("course-v1/course.json").path))
        try check(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("updated.zip").path))
        for entry in store.entries { try await store.deleteCourse(entry, includingRecords: false) }
        let reopened = AppStore(resources: resources, dataDirectory: data)
        try check(reopened.entries.isEmpty, "deleted bundled courses must not reappear after reopening")
        try check(CourseLibrary.compareVersions("1.10.0", "1.9.9") == .orderedDescending)
        try check(CourseLibrary.compareVersions("1.0.0", "1.0.0") == .orderedSame)
        print("Course library checks passed: ZIP formats and limits, hostile archives, copied content, update/rollback, record preservation, stale readers, active AI, delete/reimport/full erase, and empty library persistence.")
    }
}

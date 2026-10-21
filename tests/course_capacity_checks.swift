import Foundation

/// Exercise the loader and exact suspended job without calling remote AI or touching its original.
@MainActor final class NoGenerationCodex: CodexAuthoringService {
    var onProgress: ((String) -> Void)?
    var onLoginCompleted: ((Bool) -> Void)?
    var runs = 0
    func connect(executable: URL) async throws {}
    func accountReady() async throws -> Bool { true }
    func models() async throws -> [AuthoringModel] { [AuthoringModel(id: "no-generation", title: "No generation", effort: nil)] }
    func login() async throws -> URL { URL(string: "https://chatgpt.com/")! }
    func startThread(directory: URL, resume: String?) async throws -> String { resume ?? "no-generation" }
    func run(thread: String, prompt: String, directory: URL, model: AuthoringModel) async throws { runs += 1; throw AuthoringFailure("Unexpected AI generation; saved job must resume without rewriting.") }
    func stop() {}
}

@main struct CourseCapacityChecks {
    @MainActor static func main() async throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let fm = FileManager.default; try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let loader = try CourseLoader(webRoot: repo.appendingPathComponent("web"))
        precondition(CourseLoader.maximumContentBytes == 100_000_000)
        let jsLimit = loader.context.objectForKeyedSubscript("CourseCore")?.forProperty("MAX_CONTENT_BYTES")?.toInt32()
        precondition(jsLimit == Int32(CourseLoader.maximumContentBytes))
        let fixture = out.appendingPathComponent("capacity-fixture")
        try fm.createDirectory(at: fixture.appendingPathComponent("topics"), withIntermediateDirectories: true)
        let course: [String: Any] = ["schemaVersion":"1.1","courseId":"capacity-test","contentVersion":"1.0.0","title":"容量邊界測試","language":"zh-Hant","modules":[["id":"module","title":"教學","topics":["topic"]]],"topics":[["id":"topic","file":"topics/topic.json"]]]
        let topic: [String: Any] = ["id":"topic","title":"保留完整教材","blocks":[["id":"body","type":"markdown","file":"topics/body.md"]]]
        try AuthoringCompiler.save(course, fixture.appendingPathComponent("course.json"))
        try AuthoringCompiler.save(topic, fixture.appendingPathComponent("topics/topic.json"))
        let overhead = try Data(contentsOf: fixture.appendingPathComponent("course.json")).count + Data(contentsOf: fixture.appendingPathComponent("topics/topic.json")).count
        var content = Data("# 教材\n\n".utf8)
        content.append(Data(repeating: 0x20, count: 21_000_000 - content.count))
        try content.write(to: fixture.appendingPathComponent("topics/body.md"))
        let aboveOldLimit = try loader.load(fixture); precondition(aboveOldLimit.id == "capacity-test")
        // Sparse oversized file is rejected by byte count before its contents are read.
        let file = try FileHandle(forWritingTo: fixture.appendingPathComponent("topics/body.md"))
        try file.truncate(atOffset: UInt64(CourseLoader.maximumContentBytes - overhead + 1)); try file.close()
        do { _ = try loader.load(fixture); throw AuthoringFailure("Accepted content beyond 100 MB") }
        catch let e as CourseFailure { precondition(e.localizedDescription.contains("100 MB")) }
        try content.write(to: fixture.appendingPathComponent("topics/body.md"))
        print("Capacity passed: native/JS limits agree, >20 MB loads intact, >100 MB rejected.")
        guard CommandLine.arguments.count > 3 else { return }
        let backup = URL(fileURLWithPath: CommandLine.arguments[3])
        var job = try AuthoringMaterials.read(AuthoringJob.self, from: backup.appendingPathComponent("job.json"))
        precondition(job.completedStages == ["tutorial", "review", "conversion"])
        let data = out.appendingPathComponent("recovery"), saved = data.appendingPathComponent("AuthoringJobs/" + job.id)
        if fm.fileExists(atPath: saved.path) { try fm.removeItem(at: saved) }
        try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: backup, to: saved)
        let work = saved.appendingPathComponent("work")
        func hashes() throws -> [String: String] {
            var values: [String: String] = [:]
            for folder in ["draft", "course"] {
                if let files = fm.enumerator(at: work.appendingPathComponent(folder), includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        let relative = String(file.path.dropFirst(work.path.count + 1))
                        if relative != "course/NATIVE_VALIDATION.md" { values[relative] = try AuthoringMaterials.hash(file) }
                    }
                }
            }
            return values
        }
        let before = try hashes()
        let resources = out.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("courses","Courses"),("protocol","Protocol")] {
            let link = resources.appendingPathComponent(b)
            if !fm.fileExists(atPath: link.path) { try fm.createSymbolicLink(at: link, withDestinationURL: repo.appendingPathComponent(a)) }
        }
        let defaults = UserDefaults(suiteName:"capacity-" + UUID().uuidString)!; defaults.set("/usr/bin/true", forKey:"authoring.codexPath")
        let store = AppStore(resources:resources, dataDirectory:out.appendingPathComponent("isolated-library"), transport:{_,_ in return {}})
        let service = NoGenerationCodex(), author = CourseAuthoringStore(resources:resources,dataDirectory:data,defaults:defaults,service:service)
        defer { author.shutdown() }
        author.setImporter { zip, folder in try await store.importGeneratedCourse(zip,destination:folder) }
        author.resume(job.id)
        for _ in 0..<1800 { if !author.isBusy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        job = author.jobs.first { $0.id == job.id }!
        guard job.stage == "completed" else { throw AuthoringFailure("Saved job recovery failed: " + (job.error ?? job.stage)) }
        precondition(service.runs == 0 && job.repairAttempts == 0)
        let after = try hashes(); precondition(before == after, "Saved tutorial, review, plan and all course content must remain byte-identical")
        precondition(store.entries.contains { $0.id == job.courseID })
        try AuthoringCompiler.save(["passed":true,"jobID":job.id,"title":job.title,"aiGenerationCalls":service.runs,"unchangedContentFiles":before.count,"autoImported":true,"personalLibraryModified":false], out.appendingPathComponent("recovery-result.json"))
        print("Actual suspended job copy resumed: no AI generation, no content rewrites, native validation/ZIP/isolated auto-import passed.")
    }
}

import Foundation
import AppKit

/// Explicit opt-in integration test. Uses the signed-in local Codex account and a provided test source.
@main struct AuthoringLiveChecks {
    @MainActor static func main() async throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), cli = CommandLine.arguments[2]
        let source = URL(fileURLWithPath: CommandLine.arguments[3]), out = URL(fileURLWithPath: CommandLine.arguments[4])
        let fm = FileManager.default; try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let resources = out.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("courses","Courses"),("protocol","Protocol")] {
            let link = resources.appendingPathComponent(b)
            if !fm.fileExists(atPath: link.path) { try fm.createSymbolicLink(at: link, withDestinationURL: repo.appendingPathComponent(a)) }
        }
        let defaults = UserDefaults(suiteName: "authoring-live-" + UUID().uuidString)!
        defaults.set(cli, forKey: "authoring.codexPath")
        let store = AppStore(resources: resources, dataDirectory: out.appendingPathComponent("library"), transport: { _, _ in return {} })
        let author = CourseAuthoringStore(resources: resources, dataDirectory: out.appendingPathComponent("jobs"), defaults: defaults)
        defer { author.shutdown() }
        author.setImporter { url, dest in try await store.importGeneratedCourse(url, destination: dest) }
        if CommandLine.arguments.contains("--resume"), let job = author.jobs.first(where: { $0.stage != "completed" && !$0.inputs.isEmpty }) {
            author.resume(job.id)
        } else { author.create([source], destination: nil) }
        var last = "", ticks = 0
        while author.isBusy {
            if let stage = author.jobs.first?.stage, stage != last { print("Live authoring stage:", stage); fflush(stdout); last = stage }
            try await Task.sleep(nanoseconds: 500_000_000); ticks += 1
            if ticks > 5400 { author.cancel(); throw AuthoringFailure("Live test exceeded forty-five minutes; partial job retained.") }
        }
        guard let job = author.jobs.first else { fatalError("No live job") }
        guard job.stage == "completed" else { throw AuthoringFailure("Live job \(job.stage): \(job.error ?? author.connection)") }
        let result: [String: Any] = ["passed": true, "realCodex": true, "model": author.selectedModelID, "jobID": job.id,
            "courseID": job.courseID, "courseTitle": job.courseTitle ?? "", "completedStages": job.completedStages,
            "repairAttempts": job.repairAttempts, "autoImported": store.entries.contains { $0.id == job.courseID },
            "jobDirectory": author.workDirectory(job.id).path]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("result.json"))
        print("Live source → tutorial → review → conversion → native validation → ZIP → real library import passed.")
    }
}

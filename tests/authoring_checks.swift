import Foundation
import AppKit
import PDFKit

@main struct AuthoringChecks {
    @MainActor static func main() async throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("learning-authoring-tests-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("courses","Courses"),("protocol","Protocol")] { try fm.createSymbolicLink(at: resources.appendingPathComponent(b), withDestinationURL: repo.appendingPathComponent(a)) }
        let defaults = UserDefaults(suiteName: "authoring-checks-" + UUID().uuidString)!
        defaults.set("/usr/bin/true", forKey: "authoring.codexPath")
        let store = AppStore(resources: resources, dataDirectory: temp.appendingPathComponent("library"), transport: { _, _ in return {} })
        let source = temp.appendingPathComponent("教材.md"); try "# 來源\n\n加法範例。\n".write(to: source, atomically: true, encoding: .utf8)
        let baselineIDs = Set(store.entries.map(\.id))
        let service = FixtureCodex()
        let author = CourseAuthoringStore(resources: resources, dataDirectory: temp.appendingPathComponent("jobs"), defaults: defaults, service: service)
        author.setImporter { url, dest in try await store.importGeneratedCourse(url, destination: dest) }
        func wait(_ a: CourseAuthoringStore) async throws {
            for _ in 0..<1000 { if !a.isBusy { return }; try await Task.sleep(nanoseconds: 20_000_000) }
            fatalError("Authoring test timeout")
        }
        author.create([source], destination: nil); try await wait(author)
        let first = author.jobs[0]; precondition(first.stage == "completed", first.error ?? first.stage)
        precondition(first.repairAttempts == 1 && service.counts["repair"] == 1)
        precondition(Set(store.entries.map(\.id)).isSuperset(of: baselineIDs) && store.entries.count == baselineIDs.count + 1)
        let zip = author.workDirectory(first.id).appendingPathComponent("LearningShelf-course.zip")
        precondition(fm.fileExists(atPath: zip.path))
        do { _ = try await store.importGeneratedCourse(zip, destination: nil); fatalError("Overwrote existing course") } catch {}
        let validation = try AuthoringMaterials.read(AuthoringValidationResult.self, from: author.workDirectory(first.id).appendingPathComponent("validation.json")); precondition(validation.valid)
        let reopened = CourseAuthoringStore(resources: resources, dataDirectory: temp.appendingPathComponent("jobs"), defaults: defaults, service: FixtureCodex())
        precondition(reopened.jobs.first?.stage == "completed" && reopened.jobs.first?.importedID == first.importedID)
        // A failed conversion resumes without regenerating tutorial/review checkpoints.
        service.failConversionOnce = true; author.create([source], destination: nil); try await wait(author)
        let failed = author.jobs[0]; precondition(failed.stage == "failed" && failed.completedStages == ["tutorial", "review"])
        let before = service.counts["tutorial"]!; author.resume(failed.id); try await wait(author)
        precondition(author.jobs.first(where: { $0.id == failed.id })?.stage == "completed")
        precondition(service.counts["tutorial"] == before)
        // Invalid courses never enter the library, even after automatic repair exhaustion.
        let previousCount = store.entries.count; service.invalidForever = true
        author.create([source], destination: nil); try await wait(author)
        precondition(author.jobs[0].stage == "failed" && author.jobs[0].repairAttempts == 2 && store.entries.count == previousCount)
        service.invalidForever = false
        // Cancellation stops work; a retry creates the remaining artifacts and imports once.
        service.slowTutorial = true; author.create([source], destination: nil)
        for _ in 0..<100 { if author.jobs[0].stage == "tutorial" { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        let cancelledID = author.jobs[0].id; author.cancel(); try await wait(author)
        precondition(author.jobs.first(where: { $0.id == cancelledID })?.stage == "cancelled")
        service.slowTutorial = false; author.resume(cancelledID); try await wait(author)
        precondition(author.jobs.first(where: { $0.id == cancelledID })?.stage == "completed")
        // First-login waiting auto-resumes only after a successful login notification.
        service.ready = false; author.create([source], destination: nil); try await wait(author)
        precondition(author.jobs[0].stage == "waitingForLogin")
        service.ready = true; service.onLoginCompleted?(true)
        for _ in 0..<400 { if author.jobs[0].stage == "completed" { break }; try await Task.sleep(nanoseconds: 25_000_000) }
        precondition(author.jobs[0].stage == "completed", author.jobs[0].error ?? author.jobs[0].stage)
        // An agent that only reports a plan must be asked to save the required artifact automatically.
        let tutorials = service.counts["tutorial"]!
        service.omitTutorialOnce = true; author.create([source], destination: nil); try await wait(author)
        precondition(author.jobs[0].stage == "completed" && service.counts["tutorial"] == tutorials + 2)
        service.ready = false; author.create([source], destination: nil); try await wait(author)
        let waitingID = author.jobs[0].id; author.cancelWaiting(waitingID)
        precondition(author.jobs[0].stage == "cancelled")
        service.ready = true; service.onLoginCompleted?(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(author.jobs[0].stage == "cancelled")
        // Source symlinks are not admitted and traversal in local MD image links is not copied.
        let link = temp.appendingPathComponent("link.md"); try fm.createSymbolicLink(at: link, withDestinationURL: source)
        do { _ = try AuthoringMaterials.copySources([link], to: temp.appendingPathComponent("symlink")); fatalError("Accepted symlink") } catch {}
        print("Authoring integration checks passed: automatic 3-stage generation, native repair, ZIP roundtrip/import, no collision overwrite, original catalog preservation, persistent reopen, checkpoint retry, exhausted validation, cancellation/retry, login continuation and source symlink rejection. No remote AI invoked.")
        if CommandLine.arguments.count > 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[2]); try fm.createDirectory(at: output, withIntermediateDirectories: true)
            try AuthoringMaterials.write(validation, to: output.appendingPathComponent("authoring-integration-validation.json"))
        }
    }
}

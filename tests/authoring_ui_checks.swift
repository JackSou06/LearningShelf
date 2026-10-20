import Foundation
import AppKit
import SwiftUI

@main struct AuthoringUIChecks {
    @MainActor static func main() throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2]), fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let temp = fm.temporaryDirectory.appendingPathComponent("learning-authoring-ui-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        let resources = temp.appendingPathComponent("Resources"); try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        for (a,b) in [("web","Web"),("protocol","Protocol"),("courses","Courses")] { try fm.createSymbolicLink(at: resources.appendingPathComponent(b), withDestinationURL: repo.appendingPathComponent(a)) }
        let defaults = UserDefaults(suiteName: "authoring-ui-" + UUID().uuidString)!
        defaults.set("/usr/bin/true", forKey: "authoring.codexPath")
        let store = AppStore(resources: resources, dataDirectory: temp.appendingPathComponent("library"), transport: { _, _ in return {} })
        let service = FixtureCodex(), author = CourseAuthoringStore(resources: resources, dataDirectory: temp.appendingPathComponent("jobs"), defaults: defaults, service: service)
        author.setImporter { url, dest in try await store.importGeneratedCourse(url, destination: dest) }
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let host = NSHostingView(rootView: CourseAuthoringView(store: store, authoring: author))
        let window = NSWindow(contentRect: NSRect(x: 120, y: 80, width: 920, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "LearningShelf 製作頁面檢查"; window.isReleasedWhenClosed = false; window.contentView = host
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.close(); author.shutdown() }
        func pump(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) { app.sendEvent(event) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        }
        func screenshot(_ name: String) throws {
            pump(0.3); guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No native view bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        pump(0.8); try screenshot("authoring-ready")
        let source = temp.appendingPathComponent("加法教材.md"); try "# 教材\n\n1+2=3\n".write(to: source, atomically: true, encoding: .utf8)
        author.create([source], destination: nil)
        let end = Date().addingTimeInterval(30)
        while author.isBusy && Date() < end { pump(0.05) }
        precondition(author.jobs.first?.stage == "completed", author.jobs.first?.error ?? "No completed job")
        try screenshot("authoring-complete")
        service.invalidForever = true; author.create([source], destination: nil)
        let failureEnd = Date().addingTimeInterval(30)
        while author.isBusy && Date() < failureEnd { pump(0.05) }
        precondition(author.jobs.first?.stage == "failed")
        try screenshot("authoring-failed")
        window.setContentSize(NSSize(width: 760, height: 600)); pump(0.4); try screenshot("authoring-compact")
        precondition(host.bounds.width >= 740 && host.bounds.height >= 580)
        print("Actual SwiftUI authoring page rendered at 920x780 and 760x600: setup, completed auto-import and validation failure/retry states. Fixture Codex only; no remote AI.")
    }
}

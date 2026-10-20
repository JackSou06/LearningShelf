import Foundation

@main struct CodexAppServerChecks {
    @MainActor static func main() async throws {
        let client = CodexAppServer()
        defer { client.stop() }
        try await client.connect(executable: URL(fileURLWithPath: CommandLine.arguments[1]))
        let authenticated = try await client.accountReady()
        let models = try await client.models()
        var result: [String: Any] = ["handshake": true, "authenticated": authenticated, "imageModelCount": models.count, "inferenceRun": false]
        if CommandLine.arguments.contains("--live"), authenticated, let model = models.first {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("learningshelf-real-rpc-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let thread = try await client.startThread(directory: dir, resume: nil)
            try await client.run(thread: thread, prompt: "For this connectivity test only, write exactly LEARNINGSHELF_RPC_OK followed by a newline into smoke.txt in the current directory. Do not read other files or call network tools. Then finish.", directory: dir, model: model)
            let text = try String(contentsOf: dir.appendingPathComponent("smoke.txt"), encoding: .utf8)
            precondition(text.trimmingCharacters(in: .whitespacesAndNewlines) == "LEARNINGSHELF_RPC_OK")
            result["inferenceRun"] = true; result["sandboxedFileWritten"] = true; result["model"] = model.id
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]); print(String(data: data, encoding: .utf8)!)
    }
}

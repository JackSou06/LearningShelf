import Foundation
import Network

@main struct ShareChecks {
    @MainActor static func main() async throws {
        func check(_ expression: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) { do { let result = try expression(); precondition(result, file: file, line: line) } catch { fatalError("Check failed: \(error)", file: file, line: line) } }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let loader = try CourseLoader(webRoot: root.appendingPathComponent("web"))
        let course = try loader.load(root.appendingPathComponent("courses/linear-algebra"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LearningShelf-share-test-" + UUID().uuidString)
        let records = try RecordStore(folder: folder)
        let fakeKey = "test-secret-only-not-a-real-key"
        var sentBodies: [[String: Any]] = [], cancelled = 0
        let session = try HostSession(webRoot: root.appendingPathComponent("web"), records: records, keyProvider: { fakeKey }, transport: { request, completion in
            check(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + fakeKey)
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]; sentBodies.append(body)
            let work = DispatchWorkItem { completion(.success(["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "電腦模擬回答：" + (((body["input"] as? [[String: Any]])?.last?["content"] as? [[String: Any]])?.first?["text"] as? String ?? "")]]]], "usage": ["input_tokens": 120, "output_tokens": 30]])) }
            DispatchQueue.main.asyncAfter(deadline: .now() + (CommandLine.arguments.contains("--serve") ? 2 : 0.25), execute: work)
            return { work.cancel(); cancelled += 1 }
        })
        var seed = try session.load(course)
        seed["notes"] = ["vector": "電腦既有筆記", "linear-combination": "其他主題筆記"]
        seed["last"] = "vector"
        seed["qa"] = [["id": "existing-q", "topic": "vector", "question": "電腦既有問題", "answer": "電腦既有回答", "status": "done", "time": "2026-10-14T00:00:00Z", "version": course.version, "model": "gpt-6.1-sol", "error": ""]]
        _ = try session.save(seed, base: try session.load(course), course: course)
        let server = try ShareServer(webRoot: root.appendingPathComponent("web"), course: course, session: session)
        let link: String = try await withCheckedThrowingContinuation { continuation in server.start { continuation.resume(with: $0) } }
        var parts = URLComponents(string: link)!; parts.host = "127.0.0.1"; let baseURL = parts.url!
        if CommandLine.arguments.contains("--serve") {
            print("READY " + baseURL.absoluteString); fflush(stdout)
            while true { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        func request(_ path: String, payload: [String: Any]? = nil, origin: String? = nil) async throws -> (Data, Int) {
            var r = URLRequest(url: baseURL.appendingPathComponent(path)); r.timeoutInterval = 5
            if let payload { r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: payload) }
            if let origin { r.setValue(origin, forHTTPHeaderField: "Origin") }
            let (data, response) = try await URLSession.shared.data(for: r); return (data, (response as! HTTPURLResponse).statusCode)
        }
        func json(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        let (html, htmlCode) = try await request(""); check(htmlCode == 200 && String(data: html, encoding: .utf8)!.contains("record-sync.js"))
        let (library, _) = try await request("library.js"); let js = String(data: library, encoding: .utf8)!; check(js.contains("HOSTED_SESSION") && !js.contains(fakeKey) && !js.contains("電腦既有筆記"))
        let (info, _) = try await request("api/session"); check(try json(info)["hasKey"] as? Bool == true)
        let (raw, _) = try await request("api/records"); let before = try json(raw); check((before["notes"] as? [String: String])?["vector"] == "電腦既有筆記")
        var tablet = before; tablet["notes"] = ["vector": "平板新增筆記", "linear-combination": "其他主題筆記"]
        let (saved, savedCode) = try await request("api/records", payload: ["record": tablet, "base": before]); check(savedCode == 200); let savedRecord = try json(saved)
        check((try session.load(course)["notes"] as? [String: String])?["vector"] == "平板新增筆記")
        var desktop = savedRecord; desktop["notes"] = ["vector": "電腦更新筆記", "linear-combination": "其他主題筆記"]; _ = try session.save(desktop, base: savedRecord, course: course)
        tablet = savedRecord; tablet["notes"] = ["vector": "平板同時修改", "linear-combination": "其他主題筆記"]
        let (conflict, _) = try await request("api/records", payload: ["record": tablet, "base": savedRecord]); let text = (try json(conflict)["notes"] as! [String: String])["vector"]!; check(text.contains("電腦更新筆記") && text.contains("平板同時修改"))
        let (_, wrongOrigin) = try await request("api/records", payload: ["record": tablet, "base": savedRecord], origin: "http://unrelated.example"); check(wrongOrigin == 403)
        var foreign = tablet; foreign["courseId"] = "other"; let (_, wrongCourse) = try await request("api/records", payload: ["record": foreign, "base": savedRecord]); check(wrongCourse == 400)
        let (_, privatePath) = try await request("learning.sqlite"); check(privatePath == 404)
        let (_, sourcePath) = try await request("sources/source.pdf"); check(sourcePath == 404)
        var invalidURL = parts; invalidURL.path = "/no-token/api/records"; let (_, deniedResponse) = try await URLSession.shared.data(from: invalidURL.url!); check((deniedResponse as! HTTPURLResponse).statusCode == 404)
        let (pending, askCode) = try await request("api/ask", payload: ["topicId": "vector", "question": "平板上的問題", "requestId": "tablet-question"]); check(askCode == 200)
        check((try json(pending)["qa"] as! [[String: Any]]).last?["status"] as? String == "pending")
        let (reload, _) = try await request("api/records"); check((try json(reload)["qa"] as! [[String: Any]]).last?["status"] as? String == "pending")
        let (_, duplicateStatus) = try await request("api/ask", payload: ["topicId": "vector", "question": "平板上的問題", "requestId": "tablet-question"]); check(duplicateStatus == 200 && sentBodies.count == 1)
        let input = sentBodies[0]["input"] as! [[String: Any]], contextText = (input[0]["content"] as! [[String: Any]])[0]["text"] as! String
        check(contextText.contains("電腦更新筆記") && contextText.contains("平板同時修改") && contextText.contains("電腦既有回答") && !contextText.contains("其他主題筆記"))
        check(!contextText.contains("\n\n來源：") && !contextText.contains("\n定位："))
        try await Task.sleep(nanoseconds: 400_000_000)
        let (completed, _) = try await request("api/records"); var done = try json(completed); let question = (done["qa"] as! [[String: Any]]).last!; check(question["status"] as? String == "done" && (question["answer"] as! String).contains("平板上的問題"))
        check((try RecordStore(folder: folder).load(course.id)?["qa"] as! [[String: Any]]).last?["status"] as? String == "done")
        let (mdStatus, _) = try await request("api/markdown", payload: [:]); check(String(data: mdStatus, encoding: .utf8)!.contains("已同步"))
        let md = try String(contentsOf: MarkdownArchiveStore(folder: folder).target(course.id), encoding: .utf8); check(md.contains("平板同時修改") && md.contains("平板上的問題") && md.contains("電腦模擬回答"))
        _ = try await request("api/ask", payload: ["topicId": "vector", "question": "取消問題", "requestId": "cancel-question"])
        let (cancel, _) = try await request("api/cancel", payload: ["requestId": "cancel-question"]); check((try json(cancel)["qa"] as! [[String: Any]]).last?["status"] as? String == "cancelled" && cancelled == 1)
        let stale = done; var list = done["qa"] as! [[String: Any]]; list.removeAll { $0["id"] as? String == "tablet-question" }; done["qa"] = list; done["qaDeleted"] = ["tablet-question"]
        _ = try await request("api/records", payload: ["record": done, "base": stale]); _ = try await request("api/records", payload: ["record": stale, "base": stale])
        check(!(try session.load(course)["qa"] as! [[String: Any]]).contains { $0["id"] as? String == "tablet-question" })
        server.stop()
        print("Host sharing checks passed: computer/tablet records, conflicts, scoped access, key stays on host, authoritative topic context, reload/idempotency, saved answers, SQLite/MD, cancellation and deletion.")
    }
}

import Foundation
import AppKit
import Combine

struct AuthoringJob: Codable, Identifiable {
    var id: String
    var courseID: String
    var title: String
    var created: Date
    var updated: Date
    var stage: String
    var inputs: [AuthoringSource]
    var completedStages: [String]
    var threadID: String?
    var courseTitle: String?
    var error: String?
    var messages: [String]
    var repairAttempts: Int
    var importedID: String?
    var destinationFolder: String?
    var tutorialSourceFile: String?
    var tokenUsage: [AuthoringUsage]?
    var preparedManifest: AuthoringInputManifest?
}

@MainActor final class CourseAuthoringStore: ObservableObject {
    @Published private(set) var jobs: [AuthoringJob] = []
    @Published var selectedJobID: String?
    @Published var executablePath: String
    @Published var selectedModelID: String
    @Published private(set) var models: [AuthoringModel] = []
    @Published private(set) var connection = "尚未連線"
    @Published private(set) var authenticated = false
    @Published private(set) var connecting = false
    @Published private(set) var activeJobID: String?
    @Published var message = ""
    let directory: URL
    private let resources: URL
    private let defaults: UserDefaults
    private let service: CodexAuthoringService
    private var task: Task<Void, Never>?
    private var runner = AuthoringProcessRunner()
    private var preparation: Task<AuthoringInputManifest, Error>?
    private var visualPreparation: Task<AuthoringVisuals.Result, Error>?
    private var compilation: Task<Bool, Error>?
    private var connectionTask: Task<Void, Error>?
    private var usageStage: String?
    private var progressBuffer = ""
    private var progressFlush: DispatchWorkItem?
    private var importCourse: ((URL, String?) async throws -> LoadedCourse)?

    var selectedJob: AuthoringJob? { jobs.first { $0.id == selectedJobID } }
    var isBusy: Bool { task != nil }
    var hasPendingJob: Bool { jobs.contains { ["waitingForLogin", "interrupted"].contains($0.stage) } }
    static let stages = [("preparing", "準備教材"), ("tutorial", "撰寫教程"), ("review", "審閱修正"), ("conversion", "轉製課程"), ("validating", "驗證"), ("importing", "加入書架")]
    static func title(for stage: String) -> String {
        stages.first { $0.0 == stage }?.1 ?? ["waitingForLogin": "等待首次登入", "repairing": "自動修正", "completed": "已加入書架", "failed": "製作失敗", "cancelled": "已取消", "interrupted": "可繼續製作"][stage] ?? stage
    }

    init(resources: URL, dataDirectory: URL, defaults: UserDefaults = .standard, service: CodexAuthoringService? = nil) {
        self.resources = resources; self.directory = dataDirectory.appendingPathComponent("AuthoringJobs")
        self.defaults = defaults; self.service = service ?? CodexAppServer()
        let configured = defaults.string(forKey: "authoring.codexPath") ?? ""
        self.executablePath = configured.isEmpty ? Self.discoverExecutable() : configured
        self.selectedModelID = defaults.string(forKey: "authoring.model") ?? ""
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        self.service.onProgress = { [weak self] text in self?.recordProgress(text) }
        self.service.onUsage = { [weak self] usage in
            guard let self, let id = self.activeJobID else { return }
            self.mutate(id) { job in
                var entry = usage; entry.stage = job.tokenUsage?.last(where: { $0.threadID == usage.threadID && $0.turnID == usage.turnID })?.stage ?? self.usageStage ?? job.stage
                if !(job.tokenUsage ?? []).contains(where: { $0.threadID == entry.threadID && $0.total == entry.total }) {
                    job.tokenUsage = (job.tokenUsage ?? []) + [entry]
                }
            }
        }
        self.service.onLoginCompleted = { [weak self] success in
            guard let self else { return }
            if success {
                self.authenticated = true; self.connection = "已登入 Codex"
                Task { @MainActor in
                    await self.connect()
                    if let job = self.jobs.first(where: { $0.stage == "waitingForLogin" }) { self.resume(job.id) }
                }
            } else { self.connection = "登入未完成，請重新登入。" }
        }
    }

    static func discoverExecutable() -> String {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    func jobDirectory(_ id: String) -> URL { directory.appendingPathComponent(id) }
    func workDirectory(_ id: String) -> URL { jobDirectory(id).appendingPathComponent("work") }
    func setImporter(_ importer: @escaping (URL, String?) async throws -> LoadedCourse) { importCourse = importer }

    func connect() async {
        guard !connecting else { return }
        connecting = true; defer { connecting = false }
        do { try await ensureConnection() }
        catch { authenticated = false; connection = error.localizedDescription }
    }
    private func ensureConnection() async throws {
        if let connectionTask { return try await connectionTask.value }
        let work = Task { @MainActor in try await self.performConnection() }
        connectionTask = work
        defer { connectionTask = nil }
        try await work.value
    }
    private func performConnection() async throws {
        guard !executablePath.isEmpty, FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw AuthoringFailure("找不到 Codex。請先安裝 Codex CLI 或選擇已安裝的 Codex 執行檔。")
        }
        defaults.set(executablePath, forKey: "authoring.codexPath")
        try await service.connect(executable: URL(fileURLWithPath: executablePath))
        authenticated = try await service.accountReady()
        if !authenticated { connection = "請先登入 Codex，登入後製作會自動繼續。"; return }
        models = try await service.models()
        guard !models.isEmpty else { throw AuthoringFailure("Codex 未提供支援圖片的可用模型，請檢查登入與執行環境。") }
        if !models.contains(where: { $0.id == selectedModelID }) { selectedModelID = models[0].id }
        defaults.set(selectedModelID, forKey: "authoring.model"); connection = "Codex 已登入"
    }
    func login() async {
        do {
            guard !executablePath.isEmpty else { throw AuthoringFailure("請先選擇 Codex 執行檔。") }
            try await ensureConnection()
            if authenticated { connection = "Codex 已登入"; return }
            let url = try await service.login(); NSWorkspace.shared.open(url)
            connection = "請在瀏覽器完成登入，回到這裡後會自動繼續。"
        } catch { connection = error.localizedDescription }
    }
    func chooseExecutable() {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.message = "選擇 Codex CLI 執行檔（codex）"
        if panel.runModal() == .OK, let url = panel.url { executablePath = url.path; Task { await connect() } }
    }

    func create(_ urls: [URL], destination: String?, useExistingTutorial: Bool = false) {
        guard !isBusy else { message = "目前正在製作課程，請完成或取消後再加入。"; return }
        let id = UUID().uuidString
        let job = AuthoringJob(id: id, courseID: UUID().uuidString, title: urls.first?.deletingPathExtension().lastPathComponent ?? "新課程",
            created: Date(), updated: Date(), stage: "preparing", inputs: [], completedStages: [], messages: [], repairAttempts: 0, destinationFolder: destination)
        jobs.insert(job, at: 0); selectedJobID = id; activeJobID = id; persist(id)
        task = Task { @MainActor in
            do {
                let folder = jobDirectory(id), work = workDirectory(id)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let originals = folder.appendingPathComponent("originals")
                let copy = Task.detached { try AuthoringMaterials.copySources(urls, to: originals) }
                let sources = try await withTaskCancellationHandler { try await copy.value } onCancel: { copy.cancel() }
                let tutorials = sources.filter { ["md", "markdown"].contains($0.kind) }
                if useExistingTutorial && tutorials.count != 1 { throw AuthoringFailure("沿用教程模式需要恰好一份定稿 MD；請把其他教材以 PDF／PPTX／圖片附上。") }
                mutate(id) { $0.inputs = sources; $0.tutorialSourceFile = useExistingTutorial ? tutorials[0].file : nil }
                try Task.checkCancellation()
                try await execute(id)
            } catch { finishError(id, error) }
            task = nil; activeJobID = nil
        }
    }
    func resume(_ id: String) {
        guard !isBusy, let job = jobs.first(where: { $0.id == id }), job.stage != "completed", !job.inputs.isEmpty else { return }
        selectedJobID = id; activeJobID = id; runner = AuthoringProcessRunner()
        mutate(id) { $0.error = nil; $0.repairAttempts = 0 }
        task = Task { @MainActor in
            do { try await execute(id) } catch { finishError(id, error) }
            task = nil; activeJobID = nil
        }
    }
    func cancel() {
        guard let id = activeJobID else { return }
        mutate(id) { $0.stage = "cancelled"; $0.error = nil }
        task?.cancel(); preparation?.cancel(); visualPreparation?.cancel(); compilation?.cancel(); runner.cancel(); service.stop()
    }
    func cancelWaiting(_ id: String) {
        guard !isBusy, jobs.first(where: { $0.id == id })?.stage == "waitingForLogin" else { return }
        mutate(id) { $0.stage = "cancelled"; $0.error = nil }
    }
    func shutdown() { task?.cancel(); preparation?.cancel(); visualPreparation?.cancel(); compilation?.cancel(); runner.cancel(); service.stop(); progressFlush?.cancel(); progressFlush = nil; progressBuffer = "" }

    private func prepareVisuals(_ work: URL, manifest: AuthoringInputManifest) async throws -> AuthoringVisuals.Result {
        let native = Task.detached { try AuthoringVisuals.materialize(job: work, manifest: manifest) }
        visualPreparation = native; defer { visualPreparation = nil }
        return try await withTaskCancellationHandler { try await native.value } onCancel: { native.cancel() }
    }

    private func compile(_ work: URL, manifest: AuthoringInputManifest, courseID: String) async throws {
        let native = Task.detached { try AuthoringCompiler.materialize(job: work, manifest: manifest, courseID: courseID) }
        compilation = native; defer { compilation = nil }
        _ = try await withTaskCancellationHandler { try await native.value } onCancel: { native.cancel() }
    }

    private func checkFrozenTutorial(_ job: AuthoringJob, work: URL) throws {
        guard let file = job.tutorialSourceFile else { return }
        let source = try AuthoringVisuals.safeURL("originals/" + file, under: jobDirectory(job.id)), tutorial = try AuthoringVisuals.safeURL("draft/tutorial.md", under: work)
        if (try? AuthoringMaterials.hash(tutorial)) != (try AuthoringMaterials.hash(source)) {
            try AuthoringCompiler.copy(source, to: tutorial)
            throw AuthoringFailure("指定定稿教程被修改，已恢復原文；請重試接續，不會匯入改寫稿。")
        }
    }
    private func reviewCrops(_ id: String, thread: String, work: URL, manifest: AuthoringInputManifest, initial: AuthoringVisuals.Result, model: AuthoringModel) async throws -> AuthoringVisuals.Result {
        var visuals = initial
        for _ in 0..<3 {
            let pending = try AuthoringCheckpoints.pending(visuals.crops, job: work)
            if pending.isEmpty { return visuals }
            try AuthoringMaterials.write(AuthoringVisuals.Result(crops: pending), to: work.appendingPathComponent("PENDING_CROP_REVIEWS.json"))
            append(id, "核對 \(pending.count) 張新增或改動裁圖，沿用其餘已保存紀錄。")
            usageStage = "visual"
            defer { usageStage = nil }
            try await service.run(thread: thread, prompt: Self.visualReviewPrompt, directory: work, model: model.forStage("visual"))
            try await compile(work, manifest: manifest, courseID: jobs.first { $0.id == id }!.courseID)
            let next = try await prepareVisuals(work, manifest: manifest)
            let unchanged = pending.filter { old in next.crops.contains { $0.topicId == old.topicId && $0.imageBlockId == old.imageBlockId && $0.sha256 == old.sha256 && $0.crop == old.crop && $0.sourceImage == old.sourceImage } }
            try AuthoringCheckpoints.record(unchanged, job: work)
            visuals = next
        }
        guard try AuthoringCheckpoints.pending(visuals.crops, job: work).isEmpty else { throw AuthoringFailure("裁圖範圍連續變動三次，已保留產物與核對紀錄，請重試接續。") }
        return visuals
    }

    private func execute(_ id: String) async throws {
        guard let initial = jobs.first(where: { $0.id == id }) else { throw AuthoringFailure("找不到製作工作。") }
        let work = workDirectory(id), fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        setStage(id, "preparing")
        try AuthoringRules.install(resources: resources, job: work, courseID: initial.courseID)
        let manifest: AuthoringInputManifest
        if let cached = AuthoringCheckpoints.cachedManifest(job: work, sources: initial.inputs, trustedManifest: initial.preparedManifest) {
            manifest = cached; append(id, "沿用已核對 hash 的教材與逐頁圖片。")
        } else {
            let input = try AuthoringVisuals.safeURL("input", under: work)
            if fm.fileExists(atPath: input.path) { try fm.removeItem(at: input) }
            try fm.copyItem(at: jobDirectory(id).appendingPathComponent("originals/input"), to: input)
            let localRunner = runner, owner = self
            let preparation = Task.detached {
                try AuthoringMaterials.prepare(root: work, sources: initial.inputs, runner: localRunner) { text in
                    Task { @MainActor in owner.append(id, text) }
                }
            }
            self.preparation = preparation
            manifest = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel(); localRunner.cancel() }
            self.preparation = nil
            mutate(id) { $0.preparedManifest = manifest }
            try "1920-jpeg84-v1".write(to: work.appendingPathComponent("input-preparation.version"), atomically: true, encoding: .utf8)
        }
        if let source = initial.tutorialSourceFile, !initial.completedStages.contains("tutorial") {
            try AuthoringCompiler.copy(AuthoringVisuals.safeURL(source, under: work), to: AuthoringVisuals.safeURL("draft/tutorial.md", under: work))
            mutate(id) { $0.completedStages.append("tutorial") }
            append(id, "已沿用指定定稿教程，保留原文，接續教學核對與轉製。")
        }
        try Task.checkCancellation()
        try await ensureConnection()
        if !authenticated { setStage(id, "waitingForLogin"); return }
        guard let model = models.first(where: { $0.id == selectedModelID }) else { throw AuthoringFailure("請重新連線以取得可用模型。") }
        let current = jobs.first(where: { $0.id == id })!
        let thread = try await service.startThread(directory: work, resume: current.threadID)
        mutate(id) { $0.threadID = thread }
        let contracts = Self.contract(courseID: initial.courseID)
        try contracts.write(to: work.appendingPathComponent("OUTPUT_CONTRACT.md"), atomically: true, encoding: .utf8)
        for stage in ["tutorial", "review", "conversion"] {
            try Task.checkCancellation()
            if jobs.first(where: { $0.id == id })!.completedStages.contains(stage) { continue }
            setStage(id, stage)
            let frozen = initial.tutorialSourceFile == nil ? "" : " 指定定稿教程已在 draft/tutorial.md，必須逐位元保留；只寫獨立審閱與可區分的補充，不重寫原稿。"
            try await service.run(thread: thread, prompt: Self.prompt(stage: stage) + frozen, directory: work, model: model.forStage(stage))
            try checkFrozenTutorial(initial, work: work)
            var expected = stage == "tutorial" ? "draft/tutorial.md" : stage == "review" ? "draft/review.md" : "draft/course-plan.json"
            // Resume pre-plan jobs and retain compatibility with already-created course artifacts.
            if stage == "conversion", !fm.fileExists(atPath: work.appendingPathComponent(expected).path), fm.fileExists(atPath: work.appendingPathComponent("course/course.json").path) { expected = "course/course.json" }
            for retry in 1...2 {
                try Task.checkCancellation()
                if let contents = try? Data(contentsOf: work.appendingPathComponent(expected)), !contents.isEmpty { break }
                append(id, "此階段尚未保存完整結果，正在自動補作第\(retry)次。")
                try await service.run(thread: thread, prompt: "接續本階段，不從頭重作。只讀 rules/\(stage).md；上輪缺少必要檔案 \(expected)，保留現有產物並補完該檔案。" + Self.stageMarker(stage), directory: work, model: model.forStage(stage))
            }
            try Task.checkCancellation()
            guard let contents = try? Data(contentsOf: work.appendingPathComponent(expected)), !contents.isEmpty else { throw AuthoringFailure("Codex 未產生本階段必要檔案：\(expected)。按重試可從此階段續作。") }
            try checkFrozenTutorial(initial, work: work)
            mutate(id) { $0.completedStages.append(stage) }
        }
        let loader = try CourseLoader(webRoot: resources.appendingPathComponent("Web"))
        let temporaryLibrary = try CourseLibrary(dataDirectory: jobDirectory(id).appendingPathComponent("verification"))
        var renderedVisuals: AuthoringVisuals.Result?
        for attempt in 0...2 {
            try Task.checkCancellation(); setStage(id, attempt == 0 ? "validating" : "repairing")
            var report: AuthoringValidationResult
            var preparationError: Error?
            do {
                try await compile(work, manifest: manifest, courseID: initial.courseID)
                renderedVisuals = try await prepareVisuals(work, manifest: manifest)
            } catch {
                if error is CancellationError { throw error }
                renderedVisuals = nil; preparationError = error
            }
            // Service/network/quota failures must exit here, not become content-repair turns.
            if let visuals = renderedVisuals {
                renderedVisuals = try await reviewCrops(id, thread: thread, work: work, manifest: manifest, initial: visuals, model: model)
            }
            do {
                if let preparationError { throw preparationError }
                try checkFrozenTutorial(initial, work: work)
                let package = try temporaryLibrary.prepare(work.appendingPathComponent("course")); defer { package.discard() }
                report = try AuthoringValidation.inspect(job: work, prepared: package, loader: loader, courseID: initial.courseID, manifest: manifest, renderedVisuals: renderedVisuals)
            } catch {
                if error is CancellationError { throw error }
                report = AuthoringValidationResult(valid: false, errors: [error.localizedDescription], checks: [:], imageCount: 0, hiddenDetails: 0, limitations: [])
            }
            try AuthoringMaterials.write(report, to: work.appendingPathComponent("validation.json"))
            try AuthoringCompiler.report(job: work, result: report)
            if report.valid { break }
            if attempt == 2 { throw AuthoringFailure("自動修正兩次後仍未通過驗證，未匯入書架。\n" + report.errors.prefix(8).joined(separator: "\n")) }
            mutate(id) { $0.repairAttempts = attempt + 1 }
            append(id, "驗證未通過，正在自動修正第\(attempt + 1)次。")
            try await service.run(thread: thread, prompt: "原生驗證未通過。只讀 rules/repair.md 與 validation.json，修正列出的具體錯誤。使用計畫的工作可改 draft/course-plan.json 或其內容檔案；最終裁圖文字可直接改 course/。不寫檢查腳本或重寫報告，不重新生成完整教程。", directory: work, model: model.forStage("repairing"))
        }
        try checkFrozenTutorial(initial, work: work)
        try Task.checkCancellation(); setStage(id, "importing")
        guard let importCourse else { throw AuthoringFailure("匯入器尚未就緒，請重試。") }
        // The App, not the agent, creates the distribution archive.
        let zip = work.appendingPathComponent("LearningShelf-course.zip")
        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        let archiveRunner = runner
        let archive = Task.detached {
            try archiveRunner.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", work.appendingPathComponent("course").path, zip.path], cwd: work, log: work.appendingPathComponent("packaging.log"))
        }
        try await withTaskCancellationHandler { try await archive.value } onCancel: { archive.cancel(); archiveRunner.cancel() }
        try Task.checkCancellation()
        // Re-read and revalidate the archive immediately before committing the managed generation.
        let package = try temporaryLibrary.prepare(zip); defer { package.discard() }
        let final = try AuthoringValidation.inspect(job: work, prepared: package, loader: loader, courseID: initial.courseID, manifest: manifest, renderedVisuals: renderedVisuals)
        guard final.valid else { throw AuthoringFailure("封裝後複驗失敗，未匯入書架。") }
        let installed = try await importCourse(zip, initial.destinationFolder)
        mutate(id) { $0.stage = "completed"; $0.importedID = installed.id; $0.courseTitle = installed.title; $0.error = nil }
        append(id, "已通過驗證並加入書架：" + installed.title)
        service.stop()
    }

    private func replaceCopy(_ source: URL, to dest: URL) throws {
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
    }
    private func finishError(_ id: String, _ error: Error) {
        if error is CancellationError || jobs.first(where: { $0.id == id })?.stage == "cancelled" { mutate(id) { $0.stage = "cancelled"; $0.error = nil } }
        else { mutate(id) { $0.stage = "failed"; $0.error = error.localizedDescription }; append(id, error.localizedDescription) }
        service.stop()
    }
    private func recordProgress(_ text: String) {
        guard let id = activeJobID else { return }
        progressBuffer += text
        if progressBuffer.count > 4000 { progressBuffer = String(progressBuffer.suffix(4000)) }
        guard progressFlush == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let text = self.progressBuffer
                self.progressBuffer = ""; self.progressFlush = nil
                guard self.activeJobID == id else { return }
                self.append(id, String(text.prefix(2000)))
            }
        }
        progressFlush = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
    private func append(_ id: String, _ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mutate(id) {
            if $0.messages.last == text { return }
            $0.messages.append(text); if $0.messages.count > 150 { $0.messages.removeFirst($0.messages.count - 150) }
        }
    }
    private func setStage(_ id: String, _ stage: String) { mutate(id) { $0.stage = stage; $0.error = nil } }
    private func mutate(_ id: String, _ change: (inout AuthoringJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i]); jobs[i].updated = Date(); persist(id)
    }
    private func persist(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do { try FileManager.default.createDirectory(at: jobDirectory(id), withIntermediateDirectories: true); try AuthoringMaterials.write(job, to: jobDirectory(id).appendingPathComponent("job.json")) }
        catch { message = "製作狀態未能保存：" + error.localizedDescription }
    }
    private func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        jobs = folders.compactMap { folder -> AuthoringJob? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  var job = try? AuthoringMaterials.read(AuthoringJob.self, from: folder.appendingPathComponent("job.json")), job.id == folder.lastPathComponent else { return nil }
            if !["completed", "failed", "cancelled", "waitingForLogin", "interrupted"].contains(job.stage) { job.stage = "interrupted"; job.error = "上次製作中斷，按重試可接續已完成階段。" }
            return job
        }.sorted { $0.created > $1.created }
        selectedJobID = jobs.first?.id
    }

    static func stageMarker(_ stage: String) -> String {
        stage == "tutorial" ? " 現在只完成內部第一階段。" : stage == "review" ? " 現在完成內部第二階段。" : " 現在完成第三階段。"
    }
    static func prompt(stage: String) -> String {
        let common = "先讀 rules/\(stage).md 與 input/sources.json；完整協議僅按疑點查閱。保留完整教學，不詢問階段確認。"
        switch stage {
        case "tutorial": return common + stageMarker(stage) + "寫可獨立閱讀的 draft/tutorial.md，逐圖實際辨識並記錄於 draft/visuals/，記下需要配圖的段落和來源區域。只完成教程，不先寫 review、JSON、工具或交付報告。"
        case "review": return common + stageMarker(stage) + "讀 draft/tutorial.md 及已有逐圖觀察，依教學清單重算例子、核對條件／推導、對疑點回看來源；局部修正並寫 draft/review.md。指定定稿只保留原文、另列補充。不寫格式驗證工具。"
        default: return common + stageMarker(stage) + "讀 rules/plan.md、rules/capabilities.json、定稿與配圖依賴，只產出 draft/course-plan.json 及新增教學／完整隱藏詳述 MD。按自然段落指定 tutorialLines，重用已有圖片辨識，不重抄教程。使用既有全部區塊能力；按圖示需要設定 display 大小與對齊、就近配圖。App 負責轉製、hash、覆蓋、來源、報告、驗證與封裝。"
        }
    }
    static let visualReviewPrompt = "最終裁圖視覺核對：只讀 rules/visual.md 與 PENDING_CROP_REVIEWS.json，逐張實際觀看清單中的最終 PNG，按需要放大。更新 course/ 內同主題完整 contextOnly 詳述、description、必要可見解釋；分清裁圖可見內容、裁圖外背景與未知事項。只核對新增／改動圖，不重看已核對且未變的圖，不重寫全課、工具或報告。若必要圖例被切掉，改 course/IMAGE_MAP.json 裁圖範圍，App 直接重產後再核對。不要改 PNG、定稿、courseId 或既有 ID。"
    static func contract(courseID: String) -> String {
        "courseId=\"\(courseID)\"; contentVersion=\"1.0.0\"; schemaVersion=\"1.1\".\nRead rules/<stage>.md for the active stage; rules/plan.md defines the native compiler plan. Preserve full teaching and original sources. The App compiles, validates, renders crops, reports, packages and imports."
    }
}

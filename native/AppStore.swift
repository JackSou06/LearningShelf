import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CatalogEntry: Codable, Identifiable {
    var id: String
    var title: String
    var path: String
    var bookmark: Data?
    var version: String
    var topics: Int
    var lastOpened: Date
    var bundledFolder: String? = nil
    var managedFolder: String? = nil
}

@MainActor final class AppStore: ObservableObject {
    @Published var entries: [CatalogEntry] = []
    @Published var selected: LoadedCourse? { didSet { if oldValue?.token != selected?.token { server?.stop(); server = nil; shareURL = "" } } }
    @Published var error = ""
    @Published var shareURL = ""
    @Published var search = ""
    @Published private(set) var isPreparingToQuit = false
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress = ""
    var readerFlushers: [UUID: () async throws -> Void] = [:]
    var readerResumers: [UUID: () async -> Void] = [:]
    var readerCourseFlushers: [UUID: () async throws -> Void] = [:]
    let resources: URL
    let loader: CourseLoader
    let library: CourseLibrary
    let session: HostSession
    let records: RecordStore
    let shelfStorage: LibraryOrganizationStore
    @Published var shelf = LibraryOrganization()
    @Published var shelfLocation = "root"
    @Published var shelfSelection: Set<String> = []
    @Published var shelfNotice = ""
    @Published var renamingID: String?
    @Published var renameDraft = ""
    @Published var movingIDs: Set<String> = []
    @Published var showsMoveSheet = false
    @Published var importedCourseID: String?
    var shelfWritable = true
    var shelfReady = false
    var shelfHistory: [(String, [ShelfNode])] = []
    var shelfRedo: [(String, [ShelfNode])] = []
    var shelfScrollAnchors: [String:String] = [:]
    var shelfSelectionAnchor: String?
    var importDestinationID: String?
    private let catalogURL: URL
    private var loaded: [String: LoadedCourse] = [:]
    private var server: ShareServer?

    init(resources resourceOverride: URL? = nil, dataDirectory: URL? = nil, transport: HostSession.Transport? = nil) {
        resources = resourceOverride ?? Bundle.main.resourceURL!
        let testData = Bundle.main.bundleIdentifier?.hasSuffix(".update-test") == true ? (Bundle.main.object(forInfoDictionaryKey: "LearningShelfTestDataDirectory") as? String).map { URL(fileURLWithPath: $0) } : nil
        let data = dataDirectory ?? testData ?? ProcessInfo.processInfo.environment["LEARNING_APP_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LearningShelf")
        catalogURL = data.appendingPathComponent("catalog.json")
        shelfStorage = LibraryOrganizationStore(directory:data)
        do {
            loader = try CourseLoader(webRoot: resources.appendingPathComponent("Web"))
            records = try RecordStore(folder: data)
            library = try CourseLibrary(dataDirectory: data)
            session = try HostSession(webRoot: resources.appendingPathComponent("Web"), records: records, transport: transport)
        } catch { fatalError("App 初始化失敗：\(error.localizedDescription)") }
        if let raw = try? Data(contentsOf: catalogURL), let list = try? JSONDecoder().decode([CatalogEntry].self, from: raw) { entries = list }
        else {
            for name in ["ch3", "linear-algebra"] {
                do { try register(loader.load(resources.appendingPathComponent("Courses/" + name))) }
                catch { self.error = error.localizedDescription }
            }
        }
        do {
            shelf = try shelfStorage.load()
            var next = shelf
            next.reconcile(entries.map { (id:$0.id,title:$0.title) })
            if next != shelf { try shelfStorage.save(next); shelf = next }
            shelfLocation = validShelfLocation(shelf.preferences.location)
        } catch {
            shelfWritable = false
            shelf.reconcile(entries.map { (id:$0.id,title:$0.title) })
            self.error = "教材整理資料無法讀取，已暫停整理操作，原檔會保留。\n" + error.localizedDescription
        }
        shelfReady = true
    }
    var filtered: [CatalogEntry] { entries.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted { $0.lastOpened > $1.lastOpened } }
    private func saveCatalog(_ list: [CatalogEntry]) throws { try JSONEncoder().encode(list).write(to: catalogURL, options: .atomic) }
    private func cachedURL(_ entry: CatalogEntry) throws -> URL {
        guard CourseLibrary.validID(entry.id) else { throw CourseFailure(message: "課程 ID 無效") }
        if let folder = entry.managedFolder { return try library.snapshot(folder, courseID: entry.id) }
        return records.folder.appendingPathComponent("course-" + entry.id + ".json")
    }
    func register(_ course: LoadedCourse, managedFolder: String? = nil) throws {
        let bookmark = managedFolder == nil ? try? course.root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        let builtIn = course.root.deletingLastPathComponent().standardizedFileURL == resources.appendingPathComponent("Courses").standardizedFileURL ? course.root.lastPathComponent : nil
        let entry = CatalogEntry(id: course.id, title: course.title, path: course.root.path, bookmark: bookmark, version: course.version, topics: course.topicCount, lastOpened: Date(), bundledFolder: builtIn, managedFolder: managedFolder)
        var next = entries
        if let index = next.firstIndex(where: { $0.id == course.id }) { next[index] = entry } else { next.append(entry) }
        let snapshot = try cachedURL(entry)
        let previous = try? Data(contentsOf: snapshot)
        try JSONSerialization.data(withJSONObject: ["pack": course.pack, "model": course.model]).write(to: snapshot, options: .atomic)
        do { try saveCatalog(next) }
        catch {
            if let previous { try? previous.write(to: snapshot, options: .atomic) }
            else { try? FileManager.default.removeItem(at: snapshot) }
            throw error
        }
        entries = next
        loaded[course.id] = course
        if shelfReady { synchronizeShelf() }
    }
    private func bundledFolder(_ entry: CatalogEntry) -> String? {
        if let folder = entry.bundledFolder { return folder }
        let parts = URL(fileURLWithPath: entry.path).pathComponents
        let legacy = parts.count >= 5 && parts[parts.count-5].hasSuffix(".app") && Array(parts.suffix(4).prefix(3)) == ["Contents", "Resources", "Courses"]
        return legacy ? parts.last : nil
    }
    func root(_ entry: CatalogEntry) -> URL {
        if let folder = entry.managedFolder { return (try? library.content(folder, courseID: entry.id)) ?? library.directory.appendingPathComponent(".invalid") }
        if let folder = bundledFolder(entry), CourseLoader.safePath(folder), !folder.contains("/") {
            let candidate = resources.appendingPathComponent("Courses/" + folder)
            if let data = try? Data(contentsOf: candidate.appendingPathComponent("course.json")), let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any], manifest["courseId"] as? String == entry.id { return candidate }
        }
        if let bookmark = entry.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        return URL(fileURLWithPath: entry.path)
    }
    func open(_ entry: CatalogEntry) {
        guard !isImporting else { return }
        // Existing external links are collected into the managed library when next opened.
        if entry.managedFolder == nil && bundledFolder(entry) == nil && FileManager.default.fileExists(atPath: root(entry).path) {
            let changed = (try? loader.load(root(entry)).version) != entry.version
            Task { await importItems([root(entry)], confirmReplacement: changed, openAfterImport:true) }
            return
        }
        do {
            let course = try loader.load(root(entry))
            if course.version != entry.version {
                let alert = NSAlert()
                alert.messageText = "教材已有新版本"
                alert.informativeText = "\(entry.version) → \(course.version)\n\(entry.topics) → \(course.topicCount) 個主題。筆記與 Q&A 保留，舊版題目會提示重新作答。"
                alert.addButton(withTitle: "更新並開啟"); alert.addButton(withTitle: "使用已保存版本")
                if alert.runModal() != .alertFirstButtonReturn { openSnapshot(entry); return }
            }
            try register(course, managedFolder: entry.managedFolder)
            session.activateCourse(course)
            selected = course
        } catch { self.error = "課程無法讀取，嘗試已保存版本。\n" + error.localizedDescription; openSnapshot(entry) }
    }
    func openSnapshot(_ entry: CatalogEntry) {
        if let course = loaded[entry.id] { session.activateCourse(course); selected = course; return }
        if let url = try? cachedURL(entry), let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let pack = object["pack"] as? [String: Any], let model = object["model"] as? [String: Any] {
            let course = LoadedCourse(root: root(entry), pack: pack, model: model)
            session.activateCourse(course); selected = course
        }
    }
    func chooseFolder() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = "匯入課程 ZIP 或課程資料夾；驗證後會由 App 保存教材。"
        panel.prompt = "匯入課程"
        if panel.runModal() == .OK { Task { await importItems(panel.urls) } }
    }
    func importFolder(_ url: URL) { Task { await importItems([url]) } }
    func importItems(_ urls: [URL], confirmReplacement: Bool = true, destinationID: String? = nil, openAfterImport: Bool = false) async {
        guard !isImporting, !isPreparingToQuit else { return }
        isImporting = true
        let wasReading = selected != nil
        let target = destinationID ?? currentShelfFolder
        importDestinationID = target == "root" ? nil : target
        defer { isImporting = false; importProgress = ""; importDestinationID = nil }
        var imported: [String] = []
        var last: LoadedCourse?, failures: [String] = []
        var inputs: [URL] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !FileManager.default.fileExists(atPath: url.appendingPathComponent("course.json").path),
               let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]),
               children.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("course.json").path) }) {
                inputs += children.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("course.json").path) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else { inputs.append(url) }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        for url in inputs {
            importProgress = "正在驗證並匯入：" + url.lastPathComponent
            do {
                let library = library
                let prepared = try await Task.detached(priority: .userInitiated) { try library.prepare(url) }.value
                defer { prepared.discard() }
                if let course = try await installPrepared(prepared, confirmReplacement: confirmReplacement) { last = course; imported.append(course.id) }
            } catch { failures.append(url.lastPathComponent + "：" + error.localizedDescription) }
        }
        if let last {
            if openAfterImport || (wasReading && inputs.count == 1) { selected = last }
            else {
                selected = nil
                importedCourseID = inputs.count == 1 ? last.id : nil
                shelfNotice = "已匯入 \(imported.count) 份教材" + (failures.isEmpty ? "。" : "，\(failures.count) 份未成功。")
                shelfSelection = Set(imported.map { LibraryOrganization.courseKey($0) }).intersection(Set(shelfItems.map(\.id)))
            }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n\n") }
    }
    /// Tests can confirm replacement explicitly without opening a modal window.
    func installPrepared(_ prepared: PreparedCoursePackage, confirmReplacement: Bool) async throws -> LoadedCourse? {
        let preview = try loader.load(prepared.courseRoot)
        let old = entries.first { $0.id == preview.id }
        if let node = shelf.node(LibraryOrganization.courseKey(preview.id)), node.isTrashed {
            throw ShelfFailure(message:"此教材已在垃圾桶，請先還原後再更新；原有筆記仍保留。")
        }
        if let old {
            let order = CourseLibrary.compareVersions(preview.version, old.version)
            guard order != .orderedAscending else { throw CourseFailure(message: "匯入版本 \(preview.version) 舊於課程庫的 \(old.version)，未取代教材") }
            if confirmReplacement {
                let alert = NSAlert()
                alert.messageText = order == .orderedSame ? "重新匯入「\(preview.title)」？" : "更新「\(preview.title)」？"
                alert.informativeText = "版本 \(old.version) → \(preview.version)\n\(old.topics) → \(preview.topicCount) 個主題。\n筆記、Q&A、草稿、進度與作答紀錄保留；已變更的題目可能需要重新作答。\n目前的平板分享會在切換課程時停止。"
                alert.addButton(withTitle: "更新並保留紀錄"); alert.addButton(withTitle: "取消")
                if alert.runModal() != .alertFirstButtonReturn { return nil }
            }
        }
        guard !session.hasActiveRequests(for: preview.id) else { throw CourseFailure(message: "此課程的 AI 回答尚未完成，請等待或取消後再更新") }
        let shouldFlush = selected != nil
        if shouldFlush {
            do { for flush in Array(readerCourseFlushers.values) { try await flush() } }
            catch { await resumeReaders(); throw error }
        }
        do {
            guard !session.hasActiveRequests(for: preview.id) else { throw CourseFailure(message: "此課程的 AI 回答尚未完成，未取代教材") }
            var installed: LoadedCourse?
            try library.install(prepared, courseID: preview.id) { folder, root in
                let course = try loader.load(root)
                guard course.id == preview.id, course.version == preview.version else { throw CourseFailure(message: "課程內容在驗證後改變，未匯入") }
                try register(course, managedFolder: folder)
                installed = course
            }
            session.forgetCourse(preview.id)
            if let installed { session.activateCourse(installed) }
            if let previous = old?.managedFolder { try? library.discard(previous, courseID: preview.id) }
            if old?.managedFolder == nil { try? FileManager.default.removeItem(at: records.folder.appendingPathComponent("course-" + preview.id + ".json")) }
            if shouldFlush { selected = nil }
            return installed
        } catch { if shouldFlush { await resumeReaders() }; throw error }
    }
    private func resumeReaders() async { for resume in Array(readerResumers.values) { await resume() } }
    func requestDelete(_ entry: CatalogEntry) { trashShelfItems([LibraryOrganization.courseKey(entry.id)]) }
    func deleteCourse(_ entry: CatalogEntry, includingRecords: Bool) async throws {
        guard !isImporting, !isPreparingToQuit, CourseLibrary.validID(entry.id) else { throw CourseFailure(message: "目前無法刪除課程") }
        guard entries.contains(where: { $0.id == entry.id }) else { return }
        guard !session.hasActiveRequests(for: entry.id) else { throw CourseFailure(message: "此課程的 AI 回答尚未完成，請等待或取消後再刪除") }
        isImporting = true; importProgress = "正在刪除課程…"
        defer { isImporting = false; importProgress = "" }
        do {
            if selected?.id == entry.id { for flush in Array(readerCourseFlushers.values) { try await flush() } }
            guard !session.hasActiveRequests(for: entry.id) else { throw CourseFailure(message: "此課程的 AI 回答尚未完成，未刪除課程") }
            let next = entries.filter { $0.id != entry.id }
            try saveCatalog(next)
            do { if includingRecords { try records.delete(entry.id) } }
            catch { try saveCatalog(entries); throw error }
            if selected?.id == entry.id { selected = nil }
            session.forgetCourse(entry.id)
            loaded.removeValue(forKey: entry.id)
            entries = next
            synchronizeShelf()
            if let folder = entry.managedFolder { try library.discard(folder, courseID: entry.id) }
            try? FileManager.default.removeItem(at: records.folder.appendingPathComponent("course-" + entry.id + ".json"))
            if includingRecords {
                try? FileManager.default.removeItem(at: records.folder.appendingPathComponent("Markdown/" + entry.id + "-learning.md"))
                UserDefaults.standard.removeObject(forKey: "markdown-target:" + entry.id)
            }
        } catch { await resumeReaders(); throw error }
    }
    func remove(_ entry: CatalogEntry) { requestDelete(entry) }
    func reveal(_ entry: CatalogEntry) { NSWorkspace.shared.activateFileViewerSelecting([root(entry)]) }
    func authoring() { NSWorkspace.shared.open(resources.appendingPathComponent("Protocol/AUTHORING.md")) }
    func readProgress(_ entry: CatalogEntry) -> Double {
        guard entry.topics > 0, let record = try? records.load(entry.id) else { return 0 }
        let count = (record["seen"] as? [String])?.count ?? 0
        return min(1, Double(count) / Double(entry.topics))
    }
    func readStats(_ entry: CatalogEntry) -> String {
        guard let record = try? records.load(entry.id) else { return "尚未開始" }
        let seen = (record["seen"] as? [String])?.count ?? 0, qa = (record["qa"] as? [Any])?.count ?? 0
        return "已讀 \(seen) / \(entry.topics) · Q&A \(qa)"
    }
    func toggleShare() {
        if let server { server.stop(); self.server = nil; shareURL = ""; return }
        guard let selected else { return }
        do {
            let instance = try ShareServer(webRoot: resources.appendingPathComponent("Web"), course: selected, session: session)
            server = instance
            instance.start { [weak self] result in Task { @MainActor in
                switch result {
                case .success(let url): self?.shareURL = url
                case .failure(let error): self?.error = error.localizedDescription; self?.server = nil
                }
            } }
        } catch { self.error = error.localizedDescription }
    }
    func prepareToQuit() async throws {
        guard !isImporting else { throw CourseFailure(message: "正在匯入或刪除課程，請完成後再結束 App") }
        isPreparingToQuit = true
        for flush in Array(readerFlushers.values) { try await flush() }
        try session.prepareToQuit()
        try saveShelfViewState()
        server?.stop()
    }
    func resumeAfterCancelledQuit() async {
        session.resumeAfterCancelledQuit()
        await resumeReaders()
        isPreparingToQuit = false
    }
}

import SwiftUI
import AppKit

struct CatalogEntry: Codable, Identifiable {
    var id: String
    var title: String
    var path: String
    var bookmark: Data?
    var version: String
    var topics: Int
    var lastOpened: Date
}
@MainActor final class AppStore: ObservableObject {
    @Published var entries: [CatalogEntry] = []
    @Published var selected: LoadedCourse? { didSet { if oldValue?.token != selected?.token { server?.stop(); server=nil; shareURL="" } } }
    @Published var error = ""
    @Published var shareURL = ""
    @Published var search = ""
    let resources: URL
    let loader: CourseLoader
    let session: HostSession
    let records: RecordStore
    private let catalogURL: URL
    private var loaded: [String: LoadedCourse] = [:]
    private var server: ShareServer?
    init() {
        resources = Bundle.main.resourceURL!
        let data = ProcessInfo.processInfo.environment["LEARNING_APP_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LearningShelf")
        catalogURL = data.appendingPathComponent("catalog.json")
        do {
            loader = try CourseLoader(webRoot: resources.appendingPathComponent("Web"))
            records = try RecordStore(folder: data)
            session = try HostSession(webRoot: resources.appendingPathComponent("Web"), records: records)
        } catch { fatalError("App 初始化失敗：\(error.localizedDescription)") }
        if let raw = try? Data(contentsOf: catalogURL), let list = try? JSONDecoder().decode([CatalogEntry].self, from: raw) { entries = list }
        else {
            for name in ["ch3", "linear-algebra"] {
                do { let c = try loader.load(resources.appendingPathComponent("Courses/" + name)); register(c) } catch { self.error = error.localizedDescription }
            }
        }
    }
    var filtered: [CatalogEntry] { entries.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }.sorted { $0.lastOpened > $1.lastOpened } }
    private func saveCatalog() {
        do { try JSONEncoder().encode(entries).write(to: catalogURL, options: .atomic) }
        catch { self.error = "課程列表未能保存：" + error.localizedDescription }
    }
    private func cachedURL(_ id: String) -> URL { records.folder.appendingPathComponent("course-" + id + ".json") }
    func register(_ c: LoadedCourse) {
        let bookmark = try? c.root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let e = CatalogEntry(id: c.id, title: c.title, path: c.root.path, bookmark: bookmark, version: c.version, topics: c.topicCount, lastOpened: Date())
        if let i = entries.firstIndex(where: { $0.id == c.id }) { entries[i] = e } else { entries.append(e) }
        loaded[c.id] = c
        do { try JSONSerialization.data(withJSONObject: ["pack": c.pack, "model": c.model]).write(to: cachedURL(c.id), options: .atomic) } catch { self.error = "教材快照未保存：" + error.localizedDescription }
        saveCatalog()
    }
    func root(_ entry: CatalogEntry) -> URL {
        if let b = entry.bookmark { var stale = false; if let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return u } }
        return URL(fileURLWithPath: entry.path)
    }
    func open(_ entry: CatalogEntry) {
        do {
            let c = try loader.load(root(entry))
            if c.version != entry.version { let alert = NSAlert(); alert.messageText = "教材已有新版本"; alert.informativeText = "\(entry.version) → \(c.version)\n\(entry.topics) → \(c.topicCount) 個主題。筆記與 Q&A 保留，舊版題目會提示重新作答。"; alert.addButton(withTitle: "更新並開啟"); alert.addButton(withTitle: "使用已保存版本"); if alert.runModal() != .alertFirstButtonReturn { openSnapshot(entry); return } }
            register(c); selected = c
        } catch { self.error = "原資料夾無法讀取，嘗試已保存版本。\n" + error.localizedDescription; openSnapshot(entry) }
    }
    func openSnapshot(_ entry: CatalogEntry) {
        if let c = loaded[entry.id] { selected = c; return }
        if let data = try? Data(contentsOf: cachedURL(entry.id)), let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let pack = d["pack"] as? [String: Any], let model = d["model"] as? [String: Any] { selected = LoadedCourse(root: root(entry), pack: pack, model: model) }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.message = "選擇課程資料夾（內含 course.json）"
        if panel.runModal() == .OK, let url = panel.url { importFolder(url) }
    }
    func importFolder(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("course.json").path) {
                let c = try loader.load(url)
                if let old = entries.first(where: { $0.id == c.id }), old.path != c.root.path { let a = NSAlert();a.messageText="此課程已在列表中";a.informativeText="將以此資料夾取代原位置，保留學習紀錄。";a.addButton(withTitle:"使用此資料夾");a.addButton(withTitle:"取消");if a.runModal() != .alertFirstButtonReturn{return} }
                register(c); selected = c
            } else {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("course.json").path) }
                if children.isEmpty { throw CourseFailure(message: "此資料夾尚無課程格式。點「製作課程」取得協議，連同教材交給外部 AI 產生課程。") }
                var failures: [String] = []
                for child in children { do { register(try loader.load(child)) } catch { failures.append(child.lastPathComponent + "：" + error.localizedDescription) } }
                if !failures.isEmpty { error = failures.joined(separator: "\n") }
            }
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ e: CatalogEntry) { entries.removeAll { $0.id == e.id }; saveCatalog() }
    func reveal(_ e: CatalogEntry) { NSWorkspace.shared.activateFileViewerSelecting([root(e)]) }
    func authoring() { NSWorkspace.shared.open(resources.appendingPathComponent("Protocol/AUTHORING.md")) }
    func readStats(_ e: CatalogEntry) -> String { guard let r = try? records.load(e.id) else { return "尚未開始" }; let seen = (r["seen"] as? [String])?.count ?? 0; let qa = (r["qa"] as? [Any])?.count ?? 0; return "已讀 \(seen) / \(e.topics) · Q&A \(qa)" }
    func toggleShare() {
        if let server { server.stop(); self.server = nil; shareURL = ""; return }
        guard let selected else { return }
        do { let s = try ShareServer(webRoot: resources.appendingPathComponent("Web"), course: selected, session: session); server = s; s.start { [weak self] result in Task { @MainActor in switch result { case .success(let url): self?.shareURL = url; case .failure(let e): self?.error = e.localizedDescription; self?.server = nil } } } }
        catch { self.error = error.localizedDescription }
    }
}

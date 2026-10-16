import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfDragPayload: Codable { let libraryID: String; let ids: [String] }
let shelfDragType = "com.jacksou.learningshelf.items"

extension AppStore {
    var currentShelfFolder: String? { shelf.node(shelfLocation).flatMap { $0.kind == .folder && !$0.isTrashed ? $0.id : nil } }
    var shelfIsTrash: Bool { shelfLocation == "trash" }
    var canReorderShelf: Bool { search.isEmpty && (shelfLocation == "root" || currentShelfFolder != nil) && shelf.preferences.sort == .manual }
    func saveShelfViewState() throws {
        guard shelfWritable else { return }
        var next = shelf
        next.preferences.location = validShelfLocation(shelfLocation)
        next.preferences.scrollAnchors.merge(shelfScrollAnchors,uniquingKeysWith:{$1})
        try shelfStorage.save(next); shelf = next
    }
    var canOrganizeShelf: Bool { shelfWritable && !isImporting && !isPreparingToQuit && selected == nil }
    var shelfCanUndo: Bool { !shelfHistory.isEmpty && canOrganizeShelf }
    var shelfCanRedo: Bool { !shelfRedo.isEmpty && canOrganizeShelf }
    var shelfDisplayTitle: String {
        switch shelfLocation { case "root": return "我的教材"; case "all": return "所有教材"; case "recent": return "最近學習"; case "pinned": return "已釘選"; case "trash": return "垃圾桶"; default: return shelf.node(shelfLocation)?.name ?? "我的教材" }
    }
    func validShelfLocation(_ location: String) -> String {
        if ["root","all","recent","pinned","trash"].contains(location) { return location }
        return shelf.node(location).map { $0.kind == .folder && !$0.isTrashed ? location : "root" } ?? "root"
    }
    var shelfItems: [ShelfNode] {
        let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
        var items: [ShelfNode]
        if shelfIsTrash { items = shelf.nodes.filter { $0.trashRootID == $0.id } }
        else if !query.isEmpty && shelf.preferences.searchEverywhere { items = shelf.nodes.filter { !$0.isTrashed } }
        else {
            switch shelfLocation {
            case "all": items = shelf.nodes.filter { !$0.isTrashed }
            case "recent": items = shelf.nodes.filter { !$0.isTrashed && $0.kind == .course }
            case "pinned": items = shelf.nodes.filter { !$0.isTrashed && $0.pinned }
            default:
                if !query.isEmpty, let currentShelfFolder { let scope = shelf.descendants(of:currentShelfFolder); items = shelf.nodes.filter { scope.contains($0.id) && $0.id != currentShelfFolder && !$0.isTrashed } }
                else if !query.isEmpty { items = shelf.nodes.filter { !$0.isTrashed } }
                else { items = shelf.children(of:currentShelfFolder) }
            }
        }
        if !query.isEmpty { items = items.filter { n in n.name.localizedCaseInsensitiveContains(query) || n.courseID.flatMap { id in entries.first { $0.id == id }?.title }?.localizedCaseInsensitiveContains(query) == true } }
        let dates = Dictionary(uniqueKeysWithValues:entries.map { (LibraryOrganization.courseKey($0.id), $0.lastOpened) })
        return items.sorted { a,b in
            if shelfIsTrash, a.trashedAt != b.trashedAt { return (a.trashedAt ?? .distantPast) > (b.trashedAt ?? .distantPast) }
            if shelfLocation != "recent", a.kind != b.kind { return a.kind == .folder }
            let sort = shelfLocation == "recent" ? ShelfSort.recent : shelf.preferences.sort
            switch sort {
            case .name: let order = a.name.localizedStandardCompare(b.name); if order != .orderedSame { return order == .orderedAscending }
            case .recent: let ad = dates[a.id] ?? .distantPast, bd = dates[b.id] ?? .distantPast; if ad != bd { return ad > bd }
            case .added: if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            case .manual: if a.order != b.order { return a.order < b.order }
            }
            return a.id < b.id
        }
    }
    var shelfFolders: [ShelfNode] { shelf.nodes.filter { $0.kind == .folder && !$0.isTrashed } }
    func folderCourseCount(_ id: String) -> Int { let ids = shelf.descendants(of:id); return shelf.nodes.filter { ids.contains($0.id) && $0.kind == .course && !$0.isTrashed }.count }
    func shelfEntry(_ node: ShelfNode) -> CatalogEntry? { entries.first { $0.id == node.courseID } }
    func synchronizeShelf() {
        guard shelfWritable else { return }
        var next = shelf
        next.reconcile(entries.map { (id:$0.id,title:$0.title) },destination:importDestinationID)
        guard next != shelf else { return }
        do { try shelfStorage.save(next); shelf = next; shelfHistory.removeAll(); shelfRedo.removeAll() }
        catch { self.error = "教材已保存，但分類資訊未能保存，請重試或重新開啟 App。\n" + error.localizedDescription }
    }
    @discardableResult func changeShelf(_ title: String, _ operation: (inout LibraryOrganization) throws -> Void) -> Bool {
        guard canOrganizeShelf else { return false }
        do {
            var next = shelf
            next.reconcile(entries.map { (id:$0.id,title:$0.title) })
            try operation(&next)
            guard next.nodes != shelf.nodes else { return true }
            try shelfStorage.save(next)
            shelfHistory.append((title,shelf.nodes)); if shelfHistory.count > 50 { shelfHistory.removeFirst() }
            shelfRedo.removeAll(); shelf = next; importedCourseID = nil
            shelfLocation = validShelfLocation(shelfLocation)
            shelfSelection.formIntersection(Set(shelfItems.map(\.id)))
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func saveShelfPreferences(_ change: (inout ShelfPreferences) -> Void) {
        guard shelfWritable else { return }
        var next = shelf; change(&next.preferences)
        do { try shelfStorage.save(next); shelf = next } catch { self.error = "主頁偏好未能保存：" + error.localizedDescription }
    }
    func navigateShelf(_ location: String) {
        let previous = shelfLocation, scroll = shelfScrollAnchors[previous]
        renamingID = nil; shelfSelection.removeAll(); shelfSelectionAnchor = nil; search = ""; importedCourseID = nil
        shelfLocation = validShelfLocation(location)
        saveShelfPreferences {
            $0.location = shelfLocation
            if let scroll { $0.scrollAnchors[previous] = scroll }
            if let folder = currentShelfFolder { $0.expandedFolders.formUnion(shelf.ancestors(of:folder).map(\.id)) }
        }
    }
    func setShelfSort(_ sort: ShelfSort) { saveShelfPreferences { $0.sort = sort } }
    func setShelfLayout(_ layout: ShelfLayout) { saveShelfPreferences { $0.layout = layout } }
    func toggleShelfFolder(_ id: String) { saveShelfPreferences { if $0.expandedFolders.contains(id) { $0.expandedFolders.remove(id) } else { $0.expandedFolders.insert(id) } } }
    func selectShelfItem(_ id: String, modifiers: NSEvent.ModifierFlags = []) {
        guard renamingID == nil else { return }
        if modifiers.contains(.shift), let anchor = shelfSelectionAnchor {
            let ids = shelfItems.map(\.id)
            if let first = ids.firstIndex(of:anchor), let last = ids.firstIndex(of:id) { shelfSelection.formUnion(ids[min(first,last)...max(first,last)]); return }
        }
        if modifiers.contains(.command) { if shelfSelection.contains(id) { shelfSelection.remove(id) } else { shelfSelection.insert(id) } }
        else { shelfSelection = [id] }
        shelfSelectionAnchor = id
    }
    func openShelfItem(_ node: ShelfNode) {
        guard !node.isTrashed else { return }
        if node.kind == .folder { navigateShelf(node.id) }
        else if let entry = shelfEntry(node) { open(entry) }
    }
    func createShelfFolder() {
        guard !shelfIsTrash else { return }
        search = ""
        var created = ""
        if changeShelf("新增資料夾", { created = try $0.createFolder("未命名資料夾",parent:currentShelfFolder) }) {
            if ["all","recent","pinned"].contains(shelfLocation) { navigateShelf("root") }
            shelfSelection = [created]; startShelfRename(created)
        }
    }
    func startShelfRename(_ id: String) { guard canOrganizeShelf, let node = shelf.node(id), !node.isTrashed else { return }; renamingID = id; renameDraft = node.name }
    func finishShelfRename() {
        guard let id = renamingID else { return }
        if changeShelf("重新命名", { try $0.rename(id,to:renameDraft) }) { renamingID = nil; shelfNotice = "名稱已更新。" }
    }
    func moveShelfItems(_ ids: Set<String>, to destination: String?, before: String? = nil) {
        if changeShelf("移動項目", { try $0.move(ids,to:destination,before:before) }) {
            showsMoveSheet = false
            shelfNotice = "已移動 \(shelf.roots(of:ids).count) 個項目到「\(destination.flatMap { shelf.node($0)?.name } ?? "我的教材")」，同名項目會自動編號。"
        }
    }
    func showShelfMove(_ ids: Set<String>) { guard !ids.isEmpty else { return }; movingIDs = ids; showsMoveSheet = true }
    func shelfAllPinned(_ ids: Set<String>) -> Bool { !ids.isEmpty && ids.allSatisfy { shelf.node($0)?.pinned == true } }
    func toggleShelfPins(_ ids: Set<String>) { if changeShelf("釘選項目", { try $0.togglePins(ids) }) { shelfNotice = "已更新釘選。" } }
    func trashShelfItems(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let expanded = ids.reduce(into:Set<String>()) { $0.formUnion(shelf.descendants(of:$1)) }
        guard !shelf.nodes.contains(where:{ expanded.contains($0.id) && $0.courseID.map { session.hasActiveRequests(for:$0) } == true }) else { error = "所選教材仍有 AI 回答進行中，請完成或取消後再移到垃圾桶。"; return }
        if changeShelf("移到垃圾桶", { try $0.trash(ids) }) { shelfSelection.removeAll(); shelfNotice = "已移到垃圾桶。可按 ⌘Z 復原，或到垃圾桶還原。" }
    }
    func restoreShelfItems(_ ids: Set<String>) {
        var fallback = false
        if changeShelf("還原項目", { fallback = try $0.restore(ids) }) { shelfSelection.removeAll(); shelfNotice = fallback ? "已還原至我的教材；原資料夾仍在垃圾桶或已不存在。" : "已還原至原位置；同名項目會自動編號。" }
    }
    func undoShelfChange(redo: Bool = false) {
        guard canOrganizeShelf, let action = redo ? shelfRedo.last : shelfHistory.last else { return }
        var next = shelf; next.nodes = action.1
        do {
            try shelfStorage.save(next)
            if redo { shelfRedo.removeLast(); shelfHistory.append((action.0,shelf.nodes)) }
            else { shelfHistory.removeLast(); shelfRedo.append((action.0,shelf.nodes)) }
            shelf = next; shelfLocation = validShelfLocation(shelfLocation); shelfSelection.removeAll(); renamingID = nil
            shelfNotice = (redo ? "已重做：" : "已復原：") + action.0
        } catch { self.error = error.localizedDescription }
    }
    func requestShelfPurge(_ ids: Set<String>) {
        guard canOrganizeShelf, let all = try? shelf.purgeIDs(ids) else { return }
        let courses = shelf.nodes.filter { all.contains($0.id) && $0.kind == .course }.compactMap { n in shelfEntry(n) }
        let alert = NSAlert(); alert.messageText = "永久刪除 \(all.count) 個項目？"
        alert.informativeText = "包含 \(courses.count) 份教材及其資料夾，完成後無法復原。\n預設保留筆記、Q&A、草稿、進度與作答紀錄。"
        let records = NSButton(checkboxWithTitle:"一併永久刪除這些教材的學習紀錄",target:nil,action:nil)
        alert.accessoryView = records; alert.addButton(withTitle:"永久刪除").hasDestructiveAction = true; alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let includingRecords = records.state == .on
        Task { await permanentlyDeleteShelfItems(ids,includingRecords:includingRecords) }
    }
    func permanentlyDeleteShelfItems(_ ids: Set<String>, includingRecords: Bool) async {
        guard canOrganizeShelf else { return }
        do {
            let all = try shelf.purgeIDs(ids)
            let courses = shelf.nodes.filter { all.contains($0.id) }.compactMap { shelfEntry($0) }
            guard !courses.contains(where:{session.hasActiveRequests(for:$0.id)}) else { throw ShelfFailure(message:"教材仍有 AI 回答進行中，請完成或取消後再永久刪除。") }
            shelfHistory.removeAll(); shelfRedo.removeAll()
            for entry in courses { try await deleteCourse(entry,includingRecords:includingRecords) }
            var next = shelf; next.removePermanently(all); try shelfStorage.save(next); shelf = next
            shelfSelection.removeAll(); shelfNotice = "已永久刪除所選項目。"
        } catch { synchronizeShelf(); self.error = "永久刪除未全部完成；已完成的項目不會重複顯示。\n" + error.localizedDescription }
    }
    func shelfDragProvider(_ node: ShelfNode) -> NSItemProvider {
        let ids = shelfSelection.contains(node.id) ? shelfSelection : [node.id]
        let payload = ShelfDragPayload(libraryID:shelf.libraryID,ids:Array(ids))
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:shelfDragType,visibility:.ownProcess) { completion in completion(data,nil); return nil }
        return provider
    }
    func acceptShelfDrop(_ providers: [NSItemProvider], into destination: String?, before: String? = nil) -> Bool {
        guard canOrganizeShelf else { return false }
        if let provider = providers.first(where:{$0.hasItemConformingToTypeIdentifier(shelfDragType)}) {
            provider.loadDataRepresentation(forTypeIdentifier:shelfDragType) { data,_ in
                guard let data, let payload = try? JSONDecoder().decode(ShelfDragPayload.self,from:data) else { return }
                Task { @MainActor in
                    guard payload.libraryID == self.shelf.libraryID else { return }
                    if before != nil && self.shelf.preferences.sort != .manual { self.error = "請先切換到「自訂順序」再拖動排序。"; return }
                    self.moveShelfItems(Set(payload.ids),to:destination,before:before)
                }
            }
            return true
        }
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty, before == nil else { return false }
        Task {
            var urls: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in
                    if let data = item as? Data { continuation.resume(returning:URL(dataRepresentation:data,relativeTo:nil)) }
                    else if let url = item as? URL { continuation.resume(returning:url) }
                    else { continuation.resume(returning:nil) }
                } }
                if let url, url.isFileURL { urls.append(url) }
            }
            await importItems(urls,destinationID:destination ?? "root")
        }
        return true
    }
}

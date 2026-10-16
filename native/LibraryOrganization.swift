import Foundation

struct ShelfFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ShelfKind: String, Codable { case folder, course }
enum ShelfSort: String, Codable, CaseIterable {
    case manual, name, recent, added
    var title: String { switch self { case .manual: return "自訂順序"; case .name: return "名稱"; case .recent: return "最近學習"; case .added: return "加入時間" } }
}
enum ShelfLayout: String, Codable { case cards, list }

struct ShelfNode: Codable, Identifiable, Equatable {
    var id: String
    var kind: ShelfKind
    var courseID: String?
    var name: String
    var parentID: String?
    var order: Int
    var pinned = false
    var createdAt = Date()
    var trashRootID: String?
    var trashedAt: Date?
    var isTrashed: Bool { trashRootID != nil }
}

struct ShelfPreferences: Codable, Equatable {
    var location = "root"
    var sort = ShelfSort.manual
    var layout = ShelfLayout.cards
    var searchEverywhere = false
    var expandedFolders: Set<String> = []
    var scrollAnchors: [String:String] = [:]
}

/// Organization is independent of immutable course packages and learner records.
struct LibraryOrganization: Codable, Equatable {
    var version = 1
    var libraryID = UUID().uuidString
    var nodes: [ShelfNode] = []
    var preferences = ShelfPreferences()
    static func courseKey(_ id: String) -> String { "course:" + id }
    func node(_ id: String) -> ShelfNode? { nodes.first { $0.id == id } }
    func children(of parent: String?, includingTrash: Bool = false) -> [ShelfNode] {
        nodes.filter { $0.parentID == parent && (includingTrash || !$0.isTrashed) }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
    func descendants(of id: String) -> Set<String> {
        var found: Set<String> = [id], pending = [id]
        while let current = pending.popLast() {
            for child in nodes where child.parentID == current && !found.contains(child.id) { found.insert(child.id); pending.append(child.id) }
        }
        return found
    }
    func ancestors(of id: String) -> [ShelfNode] {
        var result: [ShelfNode] = [], cursor = node(id)?.parentID, seen: Set<String> = [id]
        while let key = cursor, !seen.contains(key), let parent = node(key) { seen.insert(key); result.insert(parent, at: 0); cursor = parent.parentID }
        return result
    }
    func path(of id: String) -> String { (["我的教材"] + ancestors(of:id).map(\.name)).joined(separator:" › ") }
    func roots(of ids: Set<String>) -> [ShelfNode] {
        nodes.filter { ids.contains($0.id) && !ancestors(of:$0.id).contains(where:{ids.contains($0.id)}) }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
    private func checkedParent(_ id: String?) throws {
        if let id { guard let n = node(id), n.kind == .folder, !n.isTrashed else { throw ShelfFailure(message:"目的資料夾不存在或已在垃圾桶。") } }
    }
    static func checkedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160, name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ShelfFailure(message:"名稱須為 1–160 個字，且不能包含換行或控制字元。")
        }
        return name
    }
    private func occupied(_ name: String, parent: String?, excluding: Set<String> = []) -> Bool {
        nodes.contains { !$0.isTrashed && $0.parentID == parent && !excluding.contains($0.id) && $0.name.compare(name,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }
    }
    func availableName(_ name: String, parent: String?, excluding: Set<String> = []) -> String {
        if !occupied(name,parent:parent,excluding:excluding) { return name }
        var suffix = 2
        while occupied(String(name.prefix(145))+" (\(suffix))",parent:parent,excluding:excluding) { suffix += 1 }
        return String(name.prefix(145))+" (\(suffix))"
    }
    private func nextOrder(_ parent: String?) -> Int { (children(of:parent,includingTrash:true).map(\.order).max() ?? -1) + 1 }
    @discardableResult mutating func createFolder(_ name: String, parent: String?) throws -> String {
        try checkedParent(parent)
        let checked = try Self.checkedName(name), id = "folder:" + UUID().uuidString
        nodes.append(ShelfNode(id:id,kind:.folder,name:availableName(checked,parent:parent),parentID:parent,order:nextOrder(parent)))
        return id
    }
    mutating func reconcile(_ courses: [(id:String,title:String)], destination: String? = nil) {
        let known = Set(courses.map { Self.courseKey($0.id) })
        nodes.removeAll { $0.kind == .course && !known.contains($0.id) }
        let parent = destination.flatMap { key in node(key).flatMap { $0.kind == .folder && !$0.isTrashed ? key : nil } }
        for course in courses where node(Self.courseKey(course.id)) == nil {
            nodes.append(ShelfNode(id:Self.courseKey(course.id),kind:.course,courseID:course.id,name:availableName(course.title,parent:parent),parentID:parent,order:nextOrder(parent)))
        }
    }
    mutating func rename(_ id: String, to raw: String) throws {
        guard let i = nodes.firstIndex(where:{$0.id == id && !$0.isTrashed}) else { throw ShelfFailure(message:"找不到這個項目。") }
        let name = try Self.checkedName(raw)
        guard !occupied(name,parent:nodes[i].parentID,excluding:[id]) else { throw ShelfFailure(message:"這個資料夾中已有同名項目，請使用其他名稱。") }
        nodes[i].name = name
    }
    mutating func move(_ ids: Set<String>, to destination: String?, before: String? = nil) throws {
        try checkedParent(destination)
        let moving = roots(of:ids)
        guard !moving.isEmpty, moving.allSatisfy({!$0.isTrashed}), ids.allSatisfy({node($0) != nil}) else { throw ShelfFailure(message:"選取的項目不存在或已在垃圾桶。") }
        for n in moving where n.kind == .folder {
            if let destination, descendants(of:n.id).contains(destination) { throw ShelfFailure(message:"無法將資料夾移入自己或自己的子資料夾。") }
        }
        let movingIDs = Set(moving.map(\.id))
        if let before { guard let target = node(before), target.parentID == destination, !target.isTrashed, !movingIDs.contains(before) else { throw ShelfFailure(message:"無效的排序位置。") } }
        var siblings = children(of:destination).filter { !movingIDs.contains($0.id) }.map(\.id)
        let insertion = before.flatMap { siblings.firstIndex(of:$0) } ?? siblings.count
        // Move each root independently so multiple same-named sources get distinct names.
        for n in moving {
            guard let i = nodes.firstIndex(where:{$0.id == n.id}) else { continue }
            if n.parentID != destination { nodes[i].name = availableName(n.name,parent:destination,excluding:[n.id]); nodes[i].parentID = destination }
        }
        siblings.insert(contentsOf:moving.map(\.id),at:insertion)
        for (order,id) in siblings.enumerated() { if let i = nodes.firstIndex(where:{$0.id == id}) { nodes[i].order = order } }
    }
    mutating func togglePins(_ ids: Set<String>) throws {
        let selected = nodes.filter { ids.contains($0.id) && !$0.isTrashed }
        guard !selected.isEmpty else { throw ShelfFailure(message:"請先選取項目。") }
        let pinned = !selected.allSatisfy(\.pinned)
        for i in nodes.indices where ids.contains(nodes[i].id) && !nodes[i].isTrashed { nodes[i].pinned = pinned }
    }
    mutating func trash(_ ids: Set<String>, at date: Date = Date()) throws {
        let selected = roots(of:ids)
        guard !selected.isEmpty, ids.allSatisfy({node($0) != nil}), selected.allSatisfy({!$0.isTrashed}) else { throw ShelfFailure(message:"請選取尚未刪除的項目。") }
        for root in selected {
            let group = descendants(of:root.id)
            for i in nodes.indices where group.contains(nodes[i].id) && !nodes[i].isTrashed { nodes[i].trashRootID = root.id; nodes[i].trashedAt = date }
        }
    }
    @discardableResult mutating func restore(_ ids: Set<String>) throws -> Bool {
        let roots = Set(ids.compactMap { node($0)?.trashRootID })
        guard !roots.isEmpty, ids.allSatisfy({node($0)?.isTrashed == true}) else { throw ShelfFailure(message:"請選取垃圾桶中的項目。") }
        var usedRootFallback = false
        for id in roots.sorted(by:{ ancestors(of:$0).count == ancestors(of:$1).count ? $0 < $1 : ancestors(of:$0).count < ancestors(of:$1).count }) {
            guard let root = node(id) else { continue }
            var destination = root.parentID
            if let parent = destination, node(parent)?.isTrashed != false { destination = nil; usedRootFallback = true }
            let group = Set(nodes.filter { $0.trashRootID == id }.map(\.id))
            let name = availableName(root.name,parent:destination,excluding:group)
            for i in nodes.indices where group.contains(nodes[i].id) { nodes[i].trashRootID = nil; nodes[i].trashedAt = nil }
            if let i = nodes.firstIndex(where:{$0.id == id}) { nodes[i].parentID = destination; nodes[i].name = name; nodes[i].order = nextOrder(destination) }
        }
        return usedRootFallback
    }
    func purgeIDs(_ ids: Set<String>) throws -> Set<String> {
        guard !ids.isEmpty, ids.allSatisfy({node($0)?.isTrashed == true}) else { throw ShelfFailure(message:"只能永久刪除垃圾桶中的項目。") }
        return ids.reduce(into:Set<String>()) { $0.formUnion(descendants(of:$1)) }
    }
    mutating func removePermanently(_ ids: Set<String>) { nodes.removeAll { ids.contains($0.id) } }
    func validate() throws {
        guard version == 1, !libraryID.isEmpty, Set(nodes.map(\.id)).count == nodes.count else { throw ShelfFailure(message:"教材整理資料版本或項目 ID 無效。") }
        let dictionary = Dictionary(uniqueKeysWithValues:nodes.map { ($0.id,$0) })
        for n in nodes {
            guard !n.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, n.order >= 0 else { throw ShelfFailure(message:"教材整理資料包含無效名稱或順序。") }
            if n.kind == .course { guard let course = n.courseID, n.id == Self.courseKey(course) else { throw ShelfFailure(message:"教材整理資料的課程 ID 不符。") } }
            else { guard n.courseID == nil, n.id.hasPrefix("folder:") else { throw ShelfFailure(message:"資料夾 ID 無效。") } }
            if let p = n.parentID { guard let parent = dictionary[p], parent.kind == .folder, parent.id != n.id, n.isTrashed || !parent.isTrashed else { throw ShelfFailure(message:"教材整理資料的父資料夾無效。") } }
            var visited: Set<String> = [n.id], cursor = n.parentID
            while let id = cursor { guard visited.insert(id).inserted else { throw ShelfFailure(message:"教材整理資料包含循環階層。") }; cursor = dictionary[id]?.parentID }
            if let root = n.trashRootID { guard let trash = dictionary[root], trash.trashRootID == root, n.trashedAt != nil, root == n.id || ancestors(of:n.id).contains(where:{$0.id == root}) else { throw ShelfFailure(message:"垃圾桶階層無效。") } }
        }
    }
}

struct LibraryOrganizationStore {
    let url: URL
    init(directory: URL) { url = directory.appendingPathComponent("organization.json") }
    func load() throws -> LibraryOrganization {
        guard FileManager.default.fileExists(atPath:url.path) else { return LibraryOrganization() }
        let state = try JSONDecoder().decode(LibraryOrganization.self,from:Data(contentsOf:url))
        try state.validate()
        return state
    }
    func save(_ state: LibraryOrganization) throws {
        try state.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(state).write(to:url,options:.atomic)
    }
}

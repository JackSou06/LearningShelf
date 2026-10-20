import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let shelfGreen = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(red:0.61,green:0.80,blue:0.68,alpha:1)
        : NSColor(red:0.21,green:0.40,blue:0.32,alpha:1)
})
private let shelfDropTypes = [shelfDragType,UTType.fileURL.identifier]

struct CourseHome: View {
    @ObservedObject var store: AppStore
    @ObservedObject var updater: AppUpdater
    var body: some View {
        HStack(spacing:0) {
            ShelfSidebar(store:store).frame(width:215)
            Divider()
            VStack(alignment:.leading,spacing:18) {
                header
                breadcrumbs
                searchBar
                selectionBar
                if !store.shelfNotice.isEmpty { notice }
                ShelfContents(store:store)
                footer
            }.padding(26).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .background(ShelfKeyboardHandler(store:store).frame(width:0,height:0))
        .sheet(isPresented:$store.showsMoveSheet) { ShelfMoveSheet(store:store) }
        .onChange(of:store.search) { _ in store.shelfSelection.formIntersection(Set(store.shelfItems.map(\.id))) }
    }
    private var header: some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:6) {
                Text("LEARNINGSHELF").font(.system(size:10,weight:.semibold)).tracking(2).foregroundColor(shelfGreen)
                Text(store.shelfDisplayTitle).font(.system(size:28,weight:.semibold)).lineLimit(1).help(store.shelfDisplayTitle)
            }
            Spacer(minLength:10)
            Button(action:store.createShelfFolder) { Label("新增資料夾",systemImage:"folder.badge.plus") }
                .disabled(!store.canOrganizeShelf || store.shelfIsTrash).help("新增資料夾 ⇧⌘N")
            Button(action: store.showCourseAuthoring) { Label("AI 製作課程", systemImage: "sparkles") }
                .disabled(store.isPreparingToQuit).accessibilityIdentifier("authoring-open")
            Button(action:store.chooseFolder) { Label("匯入教材",systemImage:"plus") }
                .buttonStyle(.borderedProminent).tint(shelfGreen).disabled(store.isImporting || store.shelfIsTrash)
        }.controlSize(.large)
    }
    private var breadcrumbs: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                Button {store.navigateShelf("root")} label:{Image(systemName:"house");Text("我的教材")}
                if let folder = store.currentShelfFolder {
                    ForEach(store.shelf.ancestors(of:folder) + [store.shelf.node(folder)!]) { n in
                        Image(systemName:"chevron.right").font(.system(size:9)).foregroundColor(.secondary)
                        Button(n.name){store.navigateShelf(n.id)}.lineLimit(1)
                    }
                } else if store.shelfLocation != "root" {
                    Image(systemName:"chevron.right").font(.system(size:9)).foregroundColor(.secondary)
                    Text(store.shelfDisplayTitle).foregroundColor(.secondary)
                }
            }.font(.system(size:12)).buttonStyle(.borderless)
        }.frame(height:22)
    }
    private var searchBar: some View {
        HStack(spacing:12) {
            HStack(spacing:9) {
                Image(systemName:"magnifyingglass").foregroundColor(.secondary)
                TextField(store.shelfIsTrash ? "搜尋垃圾桶" : "搜尋教材與資料夾",text:$store.search).textFieldStyle(.plain)
                    .accessibilityIdentifier("library-search")
                if !store.search.isEmpty { Button {store.search=""} label:{Image(systemName:"xmark.circle.fill").foregroundColor(.secondary)}.buttonStyle(.plain).help("清除搜尋") }
                if !store.shelfIsTrash {
                    Menu {
                        Button {store.saveShelfPreferences{$0.searchEverywhere=false}} label:{Label("目前範圍與子資料夾",systemImage:store.shelf.preferences.searchEverywhere ? "circle" : "checkmark")}
                        Button {store.saveShelfPreferences{$0.searchEverywhere=true}} label:{Label("整個教材庫",systemImage:store.shelf.preferences.searchEverywhere ? "checkmark" : "circle")}
                    } label:{Text(store.shelf.preferences.searchEverywhere ? "全部" : "此範圍").font(.system(size:11))}.fixedSize()
                }
            }.padding(11).background(Color(nsColor:.textBackgroundColor)).cornerRadius(10)
            Menu {
                Picker("排序",selection:Binding(get:{store.shelf.preferences.sort},set:store.setShelfSort)) {
                    ForEach(ShelfSort.allCases,id:\.self){ Text($0.title).tag($0) }
                }
            } label:{Image(systemName:"arrow.up.arrow.down")}.frame(width:28).help("排序")
                .disabled(store.shelfIsTrash || store.shelfLocation == "recent")
            Picker("顯示方式",selection:Binding(get:{store.shelf.preferences.layout},set:store.setShelfLayout)) {
                Image(systemName:"square.grid.2x2").tag(ShelfLayout.cards)
                Image(systemName:"list.bullet").tag(ShelfLayout.list)
            }.pickerStyle(.segmented).labelsHidden().frame(width:76).help("卡片或列表")
        }.font(.system(size:13))
    }
    private var selectionBar: some View {
        HStack(spacing:12) {
            if store.shelfSelection.isEmpty {
                Text("\(store.shelfItems.count) 個項目").foregroundColor(.secondary)
                Spacer()
                if store.shelfIsTrash {
                    Text("教材與學習紀錄可一併還原").foregroundColor(.secondary)
                    Button("清空垃圾桶…"){store.requestShelfPurge(Set(store.shelf.nodes.filter{$0.trashRootID == $0.id}.map(\.id)))}.disabled(store.shelfItems.isEmpty || !store.canOrganizeShelf)
                } else { Text("按 ⌘ 或 ⇧ 可多選").foregroundColor(.secondary) }
            } else {
                Button {store.shelfSelection.removeAll()} label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).help("取消選取")
                Text("已選取 \(store.shelfSelection.count) 個項目").fontWeight(.medium)
                Spacer()
                if store.shelfIsTrash {
                    Button("還原"){store.restoreShelfItems(store.shelfSelection)}
                    Button("永久刪除…",role:.destructive){store.requestShelfPurge(store.shelfSelection)}
                } else {
                    Button("移動到…"){store.showShelfMove(store.shelfSelection)}
                    Button(store.shelfAllPinned(store.shelfSelection) ? "取消釘選" : "釘選"){store.toggleShelfPins(store.shelfSelection)}
                    Button {store.trashShelfItems(store.shelfSelection)} label:{Image(systemName:"trash")}.help("移到垃圾桶 ⌘⌫")
                }
            }
        }.font(.system(size:12)).frame(height:28)
    }
    private var notice: some View {
        HStack(spacing:10) {
            Image(systemName:"checkmark.circle").foregroundColor(shelfGreen)
            Text(store.shelfNotice).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:4)
            if let id = store.importedCourseID, let entry = store.entries.first(where:{$0.id == id}) {
                Button("開始閱讀"){store.open(entry)}.font(.system(size:12))
            }
            Button {store.shelfNotice="";store.importedCourseID=nil} label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("關閉提示")
        }.padding(11).background(shelfGreen.opacity(0.07)).cornerRadius(9)
    }
    private var footer: some View {
        HStack(spacing:12) {
            Menu("更多") { Button("製作課程協議",action:store.authoring); Button("在 Finder 顯示分類資料"){NSWorkspace.shared.activateFileViewerSelecting([store.shelfStorage.url])} }
                .menuStyle(.borderlessButton).fixedSize()
            Text(AppUpdater.versionLabel).foregroundColor(.secondary)
            Spacer()
            Button("檢查更新"){updater.checkForUpdates()}.disabled(!updater.canCheckForUpdates).buttonStyle(.borderless)
        }.font(.system(size:11))
    }
}

private struct ShelfSidebar: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("教材庫",systemImage:"books.vertical").font(.system(size:17,weight:.semibold)).padding(.bottom,18)
            ShelfSidebarLink(store:store,title:"我的教材",icon:"house",location:"root")
            ShelfSidebarLink(store:store,title:"所有教材",icon:"square.stack",location:"all")
            ShelfSidebarLink(store:store,title:"最近學習",icon:"clock",location:"recent")
            ShelfSidebarLink(store:store,title:"已釘選",icon:"pin",location:"pinned")
            Divider().padding(.vertical,10)
            HStack { Text("課程資料夾").font(.system(size:11,weight:.semibold)).foregroundColor(.secondary);Spacer();Button(action:store.createShelfFolder){Image(systemName:"plus")}.buttonStyle(.plain).help("新增資料夾") }.padding(.horizontal,9)
            ScrollView {
                VStack(spacing:3) {
                    ForEach(store.shelfFolderLines(expandedOnly:true)) { line in ShelfFolderLink(store:store,line:line) }
                    if store.shelfFolders.isEmpty { Text("新增資料夾來分類課題").font(.system(size:11)).foregroundColor(.secondary).padding(.top,12) }
                    let pinnedCourses = store.shelf.nodes.filter { $0.pinned && !$0.isTrashed && $0.kind == .course }
                    if !pinnedCourses.isEmpty {
                        Divider().padding(.vertical,10)
                        Text("釘選教材").font(.system(size:11,weight:.semibold)).foregroundColor(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,9)
                        ForEach(pinnedCourses) { node in
                            Button {store.openShelfItem(node)} label:{Label(node.name,systemImage:"book.closed").font(.system(size:12)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).padding(9)}.buttonStyle(.plain)
                        }
                    }
                }
            }
            Divider()
            ShelfSidebarLink(store:store,title:"垃圾桶",icon:"trash",location:"trash")
        }.padding(16).background(shelfGreen.opacity(0.035)).tint(shelfGreen)
    }
}

private struct ShelfSidebarLink: View {
    @ObservedObject var store: AppStore
    let title: String
    let icon: String
    let location: String
    @State private var targeted = false
    var body: some View {
        Button {store.navigateShelf(location)} label:{
            HStack(spacing:10){Image(systemName:icon).frame(width:18);Text(title);Spacer();if location == "trash" {Text(String(store.shelf.nodes.filter{$0.trashRootID == $0.id}.count)).font(.system(size:11)).foregroundColor(.secondary)}}
                .font(.system(size:13)).padding(10).contentShape(Rectangle())
        }.buttonStyle(.plain).background(store.shelfLocation == location || targeted ? shelfGreen.opacity(0.12) : .clear).cornerRadius(9)
            .onDrop(of:shelfDropTypes,isTargeted:$targeted){providers in location == "root" ? store.acceptShelfDrop(providers,into:nil) : false}
    }
}

struct ShelfFolderLine: Identifiable { let node: ShelfNode; let depth: Int; var id: String {node.id} }
extension AppStore {
    func shelfFolderLines(expandedOnly: Bool) -> [ShelfFolderLine] {
        var result: [ShelfFolderLine] = []
        func visit(_ parent: String?, _ depth: Int) {
            for node in shelf.children(of:parent) where node.kind == .folder {
                result.append(ShelfFolderLine(node:node,depth:depth))
                if !expandedOnly || shelf.preferences.expandedFolders.contains(node.id) {visit(node.id,depth+1)}
            }
        }
        visit(nil,0);return result
    }
}
private struct ShelfFolderLink: View {
    @ObservedObject var store: AppStore
    let line: ShelfFolderLine
    @State private var targeted = false
    var body: some View {
        HStack(spacing:5) {
            Button {store.toggleShelfFolder(line.id)} label:{Image(systemName:store.shelf.preferences.expandedFolders.contains(line.id) ? "chevron.down" : "chevron.right").font(.system(size:9)).frame(width:14,height:28)}
                .buttonStyle(.plain).help("展開或收合資料夾")
            Button {store.navigateShelf(line.id)} label:{HStack(spacing:7){Image(systemName:"folder").foregroundColor(shelfGreen);Text(line.node.name).lineLimit(1);Spacer()}.font(.system(size:12)).frame(minHeight:32).contentShape(Rectangle())}.buttonStyle(.plain)
        }.padding(.leading,CGFloat(min(line.depth,6)*10+4)).padding(.trailing,8)
            .background(store.shelfLocation == line.id || targeted ? shelfGreen.opacity(0.12) : .clear).cornerRadius(7)
            .contextMenu { ShelfItemMenu(store:store,node:line.node) }
            .onDrag {store.shelfDragProvider(line.node)}
            .onDrop(of:shelfDropTypes,isTargeted:$targeted){store.acceptShelfDrop($0,into:line.id)}
    }
}

private struct ShelfContents: View {
    @ObservedObject var store: AppStore
    @State private var targeted = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.shelfItems.isEmpty { empty }
                else if store.shelf.preferences.layout == .cards {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:245),spacing:14,alignment:.topLeading)],spacing:14) {
                        ForEach(store.shelfItems) { node in ShelfItemCell(store:store,node:node,compact:false).id(node.id) }
                    }.padding(3)
                } else {
                    LazyVStack(spacing:7) { ForEach(store.shelfItems) { node in ShelfItemCell(store:store,node:node,compact:true).id(node.id) } }.padding(3)
                }
                Color.clear.frame(height:36).contentShape(Rectangle()).onDrop(of:shelfDropTypes,isTargeted:$targeted){providers in
                    guard !store.shelfIsTrash, store.search.isEmpty, store.shelfLocation == "root" || store.currentShelfFolder != nil else{return false};return store.acceptShelfDrop(providers,into:store.currentShelfFolder)
                }
            }.coordinateSpace(name:"shelf-scroll")
                .overlay(RoundedRectangle(cornerRadius:12).stroke(targeted ? shelfGreen : .clear,lineWidth:2).allowsHitTesting(false))
                .onPreferenceChange(ShelfItemPositions.self) { positions in
                    if let first = positions.filter({position in position.value >= -20 && store.shelfItems.contains(where:{$0.id == position.key})}).min(by:{$0.value < $1.value}) {store.shelfScrollAnchors[store.shelfLocation] = first.key}
                }
                .onChange(of:store.shelfLocation) { _ in restoreScroll(proxy) }
                .onAppear {restoreScroll(proxy)}
        }
    }
    private func restoreScroll(_ proxy: ScrollViewProxy) {
        let id = store.shelf.preferences.scrollAnchors[store.shelfLocation]
        if let id {DispatchQueue.main.async {proxy.scrollTo(id,anchor:.top)}}
    }
    private var empty: some View {
        VStack(spacing:14) {
            Image(systemName:store.shelfIsTrash ? "trash" : store.search.isEmpty ? "folder.badge.plus" : "magnifyingglass").font(.system(size:38,weight:.light)).foregroundColor(shelfGreen)
            Text(!store.search.isEmpty ? "找不到符合的項目" : store.shelfIsTrash ? "垃圾桶是空的" : "準備好整理這門課了嗎？").font(.system(size:20,weight:.medium))
            Text(!store.search.isEmpty ? "試試其他關鍵字，或切換搜尋範圍。" : store.shelfIsTrash ? "移到這裡的教材可以還原，學習紀錄會保留。" : "匯入教材，或新增子資料夾來分類課題。").font(.system(size:13)).foregroundColor(.secondary)
            if !store.search.isEmpty {Button("清除搜尋"){store.search=""}}
            else if !store.shelfIsTrash {HStack {Button("新增資料夾",action:store.createShelfFolder);Button("匯入教材",action:store.chooseFolder)}}
        }.frame(maxWidth:.infinity).padding(.vertical,70)
    }
}
private struct ShelfItemPositions: PreferenceKey {
    static let defaultValue: [String:CGFloat] = [:]
    static func reduce(value: inout [String:CGFloat], nextValue: () -> [String:CGFloat]) {value.merge(nextValue(),uniquingKeysWith:{$1})}
}

private struct ShelfItemCell: View {
    @ObservedObject var store: AppStore
    let node: ShelfNode
    let compact: Bool
    @State private var targeted = false
    @State private var insertion = false
    @FocusState private var editingName: Bool
    private var selected: Bool {store.shelfSelection.contains(node.id)}
    var body: some View {
        Group {
            if compact { HStack(spacing:14){icon.frame(width:35);nameAndInfo;Spacer(minLength:4);openButton;menu}.padding(14) }
            else { VStack(alignment:.leading,spacing:14){HStack{icon;Spacer();if node.pinned {Image(systemName:"pin.fill").font(.system(size:11)).foregroundColor(shelfGreen)};menu};nameAndInfo.frame(minHeight:80,alignment:.topLeading);HStack{openButton;Spacer();if node.kind == .folder {Text("資料夾").font(.system(size:11)).foregroundColor(.secondary)}}}.padding(19) }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(selected ? shelfGreen.opacity(0.08) : Color(nsColor:.textBackgroundColor))
        .cornerRadius(compact ? 10 : 14)
        .overlay(RoundedRectangle(cornerRadius:compact ? 10 : 14).stroke(selected || targeted ? shelfGreen.opacity(0.7) : Color.primary.opacity(0.08),lineWidth:selected || targeted ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count:2){store.openShelfItem(node)}
        .onTapGesture {store.selectShelfItem(node.id,modifiers:NSEvent.modifierFlags)}
        .contextMenu {ShelfItemMenu(store:store,node:node)}
        .onDrag {node.isTrashed ? NSItemProvider() : store.shelfDragProvider(node)}
        .overlay(alignment:.top) { if insertion { Capsule().fill(shelfGreen).frame(height:3).padding(.horizontal,4).offset(y:-2).allowsHitTesting(false) } }
        .onDrop(of:shelfDropTypes,delegate:ShelfCellDropDelegate(store:store,node:node,targeted:$targeted,insertion:$insertion))
        .onChange(of:store.renamingID){editingName = $0 == node.id}
        .onAppear {editingName = store.renamingID == node.id}
        .background(GeometryReader {geo in Color.clear.preference(key:ShelfItemPositions.self,value:[node.id:geo.frame(in:.named("shelf-scroll")).minY])})
        .accessibilityElement(children:.contain).accessibilityLabel(node.name).accessibilityIdentifier("shelf-item-"+node.id)
    }
    private var icon: some View {Image(systemName:node.kind == .folder ? "folder.fill" : "book.closed").font(.system(size:compact ? 24 : 30,weight:.light)).foregroundColor(node.kind == .folder ? Color(red:0.69,green:0.53,blue:0.28) : shelfGreen)}
    private var nameAndInfo: some View {
        VStack(alignment:.leading,spacing:8) {
            if store.renamingID == node.id {
                TextField("名稱",text:$store.renameDraft).textFieldStyle(.roundedBorder).focused($editingName).onSubmit(store.finishShelfRename).onExitCommand{store.renamingID=nil}
                    .accessibilityIdentifier("library-rename")
            } else {Text(node.name).font(.system(size:compact ? 14 : 17,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).help(node.name)}
            if node.isTrashed {
                Text(node.trashedAt.map {"刪除於 " + $0.formatted(date:.abbreviated,time:.omitted)} ?? "已移到垃圾桶").font(.system(size:11)).foregroundColor(.secondary)
            } else if let entry = store.shelfEntry(node) {
                Text(store.readStats(entry)).font(.system(size:12)).foregroundColor(.secondary)
                if !compact {ProgressView(value:store.readProgress(entry)).tint(shelfGreen)}
            } else {Text("\(store.folderCourseCount(node.id)) 份教材").font(.system(size:12)).foregroundColor(.secondary)}
            if !store.search.isEmpty || ["all","recent","pinned","trash"].contains(store.shelfLocation) {
                Text(store.shelf.path(of:node.id)).font(.system(size:10)).foregroundColor(.secondary).lineLimit(1).help(store.shelf.path(of:node.id))
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    @ViewBuilder private var openButton: some View {
        if node.isTrashed {Button("還原"){store.restoreShelfItems([node.id])}.controlSize(.small)}
        else {Button(node.kind == .folder ? "開啟資料夾" : "繼續學習"){store.openShelfItem(node)}.controlSize(.small).tint(shelfGreen)}
    }
    private var menu: some View {Menu{ShelfItemMenu(store:store,node:node)}label:{Image(systemName:"ellipsis").frame(width:22,height:24)}.menuStyle(.borderlessButton).fixedSize().help("項目選項")}
}

private struct ShelfItemMenu: View {
    @ObservedObject var store: AppStore
    let node: ShelfNode
    private var ids: Set<String> {store.shelfSelection.contains(node.id) ? store.shelfSelection : [node.id]}
    var body: some View {
        if node.isTrashed {
            Button("還原"){store.restoreShelfItems(ids)}
            Button("永久刪除…",role:.destructive){store.requestShelfPurge(ids)}
        } else {
            Button(node.kind == .folder ? "開啟資料夾" : "繼續學習"){store.openShelfItem(node)}
            Divider()
            Button("重新命名"){store.startShelfRename(node.id)}.disabled(ids.count != 1)
            Button("移動到…"){store.showShelfMove(ids)}
            Button(store.shelfAllPinned(ids) ? "取消釘選" : "釘選"){store.toggleShelfPins(ids)}
            Button("資訊"){store.showShelfInformation(node)}
            if let entry = store.shelfEntry(node) {
                Button("在 Finder 顯示教材"){store.reveal(entry)}
                Button("更新教材…",action:store.chooseFolder)
            }
            Divider()
            Button("移到垃圾桶",role:.destructive){store.trashShelfItems(ids)}
        }
    }
}

private struct ShelfMoveSheet: View {
    @ObservedObject var store: AppStore
    @State private var destination = "root"
    @State private var query = ""
    private var excluded: Set<String> {store.movingIDs.reduce(into:Set<String>()){$0.formUnion(store.shelf.descendants(of:$1))}}
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("移動 \(store.movingIDs.count) 個項目").font(.system(size:22,weight:.semibold))
            Text("選擇目的資料夾，同名項目會自動編號保留。").font(.system(size:13)).foregroundColor(.secondary)
            TextField("搜尋目的資料夾",text:$query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing:4) {
                    destinationRow(title:"我的教材",id:"root",depth:0)
                    ForEach(store.shelfFolderLines(expandedOnly:false).filter{!excluded.contains($0.id) && (query.isEmpty || $0.node.name.localizedCaseInsensitiveContains(query))}) {line in destinationRow(title:line.node.name,id:line.id,depth:line.depth+1)}
                }
            }.frame(height:260)
            Divider()
            HStack {Spacer();Button("取消"){store.showsMoveSheet=false}.keyboardShortcut(.cancelAction);Button("移動到這裡"){store.moveShelfItems(store.movingIDs,to:destination == "root" ? nil : destination)}.buttonStyle(.borderedProminent).tint(shelfGreen).keyboardShortcut(.defaultAction)}
        }.padding(26).frame(width:460)
    }
    private func destinationRow(title: String,id: String,depth: Int) -> some View {
        Button {destination=id} label:{HStack{Image(systemName:id == "root" ? "house" : "folder");Text(title).lineLimit(1);Spacer();if destination == id{Image(systemName:"checkmark")}}.font(.system(size:13)).padding(11).padding(.leading,CGFloat(min(depth,8)*14)).frame(maxWidth:.infinity).contentShape(Rectangle())}
            .buttonStyle(.plain).background(destination == id ? shelfGreen.opacity(0.1) : .clear).cornerRadius(8)
    }
}

private struct ShelfKeyboardHandler: NSViewRepresentable {
    @ObservedObject var store: AppStore
    final class Coordinator {var token: Any?;deinit {if let token{NSEvent.removeMonitor(token)}}}
    func makeCoordinator() -> Coordinator {Coordinator()}
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.token = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak view, weak store] event in
            guard let store, let view, event.window === view.window, store.selected == nil, !store.showsMoveSheet, NSApp.modalWindow == nil,
                  !(event.window?.firstResponder is NSTextView), store.renamingID == nil else{return event}
            let key = event.charactersIgnoringModifiers?.lowercased() ?? "", flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                if key == "a" {store.shelfSelection = Set(store.shelfItems.map(\.id));return nil}
                if key == "z" {store.undoShelfChange(redo:flags.contains(.shift));return nil}
                if key == "n" && flags.contains(.shift) {store.createShelfFolder();return nil}
                if event.keyCode == 51 {if store.shelfIsTrash{store.requestShelfPurge(store.shelfSelection)}else{store.trashShelfItems(store.shelfSelection)};return nil}
                if key == "o" {store.openSelectedShelfItem();return nil}
                if event.keyCode == 126 {store.navigateShelf(store.currentShelfFolder.flatMap{store.shelf.node($0)?.parentID} ?? "root");return nil}
            }
            if event.keyCode == 36, store.shelfSelection.count == 1, let id = store.shelfSelection.first {store.startShelfRename(id);return nil}
            if event.keyCode == 53 {store.shelfSelection.removeAll();return nil}
            return event
        }
        return view
    }
    func updateNSView(_ nsView: NSView,context: Context) {}
    static func dismantleNSView(_ view: NSView,coordinator: Coordinator) {if let token=coordinator.token{NSEvent.removeMonitor(token);coordinator.token=nil}}
}

extension AppStore {
    func openSelectedShelfItem() {if shelfSelection.count == 1,let id=shelfSelection.first,let node=shelf.node(id){openShelfItem(node)}}
    func showShelfInformation(_ node: ShelfNode) {
        let alert=NSAlert();alert.messageText=node.name
        if let entry=shelfEntry(node){alert.informativeText="教材原名：\(entry.title)\n版本：\(entry.version)\n主題數：\(entry.topics)\n位置：\(shelf.path(of:node.id))\n\(readStats(entry))"}
        else {alert.informativeText="資料夾\n位置：\(shelf.path(of:node.id))\n包含 \(folderCourseCount(node.id)) 份教材"}
        alert.addButton(withTitle:"完成");alert.runModal()
    }
}

private struct ShelfCellDropDelegate: DropDelegate {
    let store: AppStore
    let node: ShelfNode
    @Binding var targeted: Bool
    @Binding var insertion: Bool
    func validateDrop(info: DropInfo) -> Bool { !node.isTrashed && store.canOrganizeShelf && (node.kind == .folder || store.canReorderShelf) }
    func dropEntered(info: DropInfo) {targeted=true;insertion=shouldInsert(info)}
    func dropUpdated(info: DropInfo) -> DropProposal? {insertion=shouldInsert(info);return DropProposal(operation:info.hasItemsConforming(to:[shelfDragType]) ? .move : .copy)}
    func dropExited(info: DropInfo) {targeted=false;insertion=false}
    private func shouldInsert(_ info: DropInfo) -> Bool { store.canReorderShelf && info.hasItemsConforming(to:[shelfDragType]) && (node.kind == .course || info.location.y < 16) }
    func performDrop(info: DropInfo) -> Bool {
        let before=shouldInsert(info);targeted=false;insertion=false
        if before {return store.acceptShelfDrop(info.itemProviders(for:[shelfDragType]),into:node.parentID,before:node.id)}
        return node.kind == .folder ? store.acceptShelfDrop(info.itemProviders(for:shelfDropTypes),into:node.id) : false
    }
}

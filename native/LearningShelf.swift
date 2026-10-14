import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main struct LearningShelf: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("學習工具") {
            VStack(spacing:0) {
                if let course=store.selected {
                    if !store.shareURL.isEmpty { VStack(alignment:.leading,spacing:4) { Text("平板筆記與 Q&A 同步至此 Mac；AI 使用此 Mac 的 API 設定。").font(.system(size:12)).foregroundColor(.secondary);HStack {Text(store.shareURL).font(.system(size:12,design:.monospaced)).textSelection(.enabled);Button("複製網址"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(store.shareURL,forType:.string)};Spacer();Button("停止分享"){store.toggleShare()} } }.padding(10).background(Color.gray.opacity(0.07)) }
                    WebReader(store:store,course:course).id(course.token)
                } else { CourseHome(store:store) }
            }
            .frame(minWidth:760,minHeight:580)
            .toolbar {
                if store.selected != nil {Button(store.shareURL.isEmpty ? "分享到平板":"停止分享"){store.toggleShare()}}
            }
            .alert("課程訊息",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0{store.error=""}})) {Button("複製修正清單"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(store.error,forType:.string);store.error=""};Button("關閉",role:.cancel){store.error=""}} message: {Text(store.error)}
        }.defaultSize(width:1100,height:820)
        .commands {CommandGroup(replacing:.newItem){Button("開啟課程資料夾…"){store.chooseFolder()}.keyboardShortcut("o");Button("課程主頁"){store.selected=nil}.keyboardShortcut("h",modifiers:[.command,.shift]);Button("製作課程協議"){store.authoring()}}}
    }
}
struct CourseHome: View {
    @ObservedObject var store:AppStore
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            HStack {Text("課程").font(.system(size:28,weight:.semibold));Spacer();Button("開啟資料夾"){store.chooseFolder()};Button("製作課程"){store.authoring()} }
            TextField("搜尋課程",text:$store.search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing:0){ForEach(store.filtered){entry in
                    HStack(alignment:.center,spacing:16){VStack(alignment:.leading,spacing:7){Text(entry.title).font(.system(size:17,weight:.medium));Text(store.readStats(entry)+" · 版本 "+entry.version).font(.system(size:12)).foregroundColor(.secondary)};Spacer();Button("繼續學習"){store.open(entry)}.buttonStyle(.bordered) }.padding(.vertical,22)
                        .contextMenu {Button("在 Finder 顯示"){store.reveal(entry)};Button("重新定位…"){store.chooseFolder()};Button("從列表移除"){store.remove(entry)}}
                    Divider()
                }}
            }
            if store.entries.isEmpty {Text("開啟課程資料夾開始學習。").foregroundColor(.secondary)}
        }.padding(40).frame(maxWidth:1000).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil){providers in guard let provider=providers.first else{return false};provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){item,_ in if let data=item as? Data,let url=URL(dataRepresentation:data,relativeTo:nil){Task{@MainActor in store.importFolder(url)}}};return true}
    }
}

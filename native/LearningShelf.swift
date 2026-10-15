import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main struct LearningShelf: App {
    @NSApplicationDelegateAdaptor(LearningAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var updater = AppUpdater()
    @State private var isDropTargeted = false
    var body: some Scene {
        WindowGroup("學習工具") {
            VStack(spacing:0) {
                if let course=store.selected {
                    if !store.shareURL.isEmpty { VStack(alignment:.leading,spacing:4) { Text("平板筆記與 Q&A 同步至此 Mac；AI 使用此 Mac 的 API 設定。").font(.system(size:12)).foregroundColor(.secondary);HStack {Text(store.shareURL).font(.system(size:12,design:.monospaced)).textSelection(.enabled);Button("複製網址"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(store.shareURL,forType:.string)};Spacer();Button("停止分享"){store.toggleShare()} } }.padding(10).background(Color.gray.opacity(0.07)) }
                    WebReader(store:store,course:course).id(course.token)
                } else { CourseHome(store:store,updater:updater) }
            }
            .disabled(store.isPreparingToQuit || store.isImporting)
            .overlay {
                if store.isImporting {
                    VStack(spacing:12) { ProgressView(); Text(store.importProgress).font(.system(size:13)) }
                        .padding(24).background(.regularMaterial).cornerRadius(12)
                }
            }
            .overlay { if isDropTargeted { RoundedRectangle(cornerRadius:12).stroke(Color.accentColor, style:StrokeStyle(lineWidth:3,dash:[8])).padding(8).allowsHitTesting(false) } }
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:$isDropTargeted) { providers in
                guard !store.isImporting, !store.isPreparingToQuit else { return false }
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item, _ in
                                if let data = item as? Data { continuation.resume(returning:URL(dataRepresentation:data,relativeTo:nil)) }
                                else if let url = item as? URL { continuation.resume(returning:url) }
                                else if let text = item as? String { continuation.resume(returning:URL(string:text)) }
                                else { continuation.resume(returning:nil) }
                            }
                        }
                        if let url, url.isFileURL { urls.append(url) }
                    }
                    await store.importItems(urls)
                }
                return !providers.isEmpty
            }
            .onAppear { appDelegate.store = store }
            .frame(minWidth:760,minHeight:580)
            .toolbar {
                if store.selected != nil {Button("匯入課程"){store.chooseFolder()};Button(store.shareURL.isEmpty ? "分享到平板":"停止分享"){store.toggleShare()}}
            }
            .alert("課程訊息",isPresented:Binding(get:{!store.error.isEmpty},set:{if !$0{store.error=""}})) {Button("複製修正清單"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(store.error,forType:.string);store.error=""};Button("關閉",role:.cancel){store.error=""}} message: {Text(store.error)}
        }.defaultSize(width:1100,height:820)
        .commands {
            CommandGroup(after:.appInfo) { Button("檢查更新…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates || store.isPreparingToQuit) }
            CommandGroup(replacing:.newItem){Button("匯入課程…"){store.chooseFolder()}.keyboardShortcut("o");Button("課程主頁"){store.selected=nil}.keyboardShortcut("h",modifiers:[.command,.shift]);Button("製作課程協議"){store.authoring()}}
        }
    }
}
struct CourseHome: View {
    @ObservedObject var store: AppStore
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Text("課程").font(.system(size:28,weight:.semibold))
                Spacer()
                Button("匯入課程"){store.chooseFolder()}
                Button("製作課程"){store.authoring()}
            }
            Text("將課程 ZIP 拖到這裡，或匯入課程資料夾。驗證後由 App 保存教材。").font(.system(size:13)).foregroundColor(.secondary)
            HStack {
                Text(AppUpdater.versionLabel).foregroundColor(.secondary)
                Spacer()
                Button("檢查更新"){updater.checkForUpdates()}.disabled(!updater.canCheckForUpdates)
            }.font(.system(size:12))
            TextField("搜尋課程",text:$store.search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing:0) {
                    ForEach(store.filtered) { entry in
                        HStack(spacing:16) {
                            VStack(alignment:.leading,spacing:7) {
                                Text(entry.title).font(.system(size:17,weight:.medium))
                                Text(store.readStats(entry)+" · 版本 "+entry.version).font(.system(size:12)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("繼續學習"){store.open(entry)}.buttonStyle(.bordered)
                            Button { store.requestDelete(entry) } label: { Image(systemName:"trash").padding(5) }
                                .buttonStyle(.borderless).help("刪除課程").accessibilityLabel("刪除課程："+entry.title)
                        }.padding(.vertical,20)
                        .contextMenu {
                            Button("在 Finder 顯示"){store.reveal(entry)}
                            Button("更新教材…"){store.chooseFolder()}
                            Button("刪除課程…",role:.destructive){store.requestDelete(entry)}
                        }
                        Divider()
                    }
                }
            }
            if store.entries.isEmpty { Text("匯入第一門課程開始學習。").foregroundColor(.secondary) }
        }.padding(40).frame(maxWidth:1000).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
    }
}

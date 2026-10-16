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
            CommandGroup(replacing:.newItem) {
                Button("新增資料夾",action:store.createShelfFolder).keyboardShortcut("n",modifiers:[.command,.shift]).disabled(!store.canOrganizeShelf || store.shelfIsTrash)
                Button("匯入教材…",action:store.chooseFolder).keyboardShortcut("i",modifiers:[.command,.shift]).disabled(store.isImporting)
                Button("開啟所選項目",action:store.openSelectedShelfItem).keyboardShortcut("o").disabled(store.selected != nil || store.shelfSelection.count != 1)
                Button("教材主頁"){store.selected=nil}.keyboardShortcut("h",modifiers:[.command,.shift])
                Button("製作課程協議",action:store.authoring)
            }
            CommandGroup(replacing:.undoRedo) {
                Button("復原") { if store.selected != nil || NSApp.keyWindow?.firstResponder is NSTextView {NSApp.sendAction(Selector(("undo:")),to:nil,from:nil)} else {store.undoShelfChange()} }.keyboardShortcut("z").disabled(store.selected == nil && !(NSApp.keyWindow?.firstResponder is NSTextView) && !store.shelfCanUndo)
                Button("重做") { if store.selected != nil || NSApp.keyWindow?.firstResponder is NSTextView {NSApp.sendAction(Selector(("redo:")),to:nil,from:nil)} else {store.undoShelfChange(redo:true)} }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(store.selected == nil && !(NSApp.keyWindow?.firstResponder is NSTextView) && !store.shelfCanRedo)
            }
        }
    }
}

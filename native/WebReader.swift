import SwiftUI
import WebKit
import AppKit

struct WebReader: NSViewRepresentable {
    @ObservedObject var store: AppStore
    let course: LoadedCourse
    func makeCoordinator() -> Coordinator { Coordinator(store: store, course: course) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "learning")
        config.userContentController.add(context.coordinator, name: "learning")
        let view = WKWebView(frame: .zero, configuration: config)
        context.coordinator.web = view; view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "learning://app/index.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.configuration.userContentController.removeScriptMessageHandler(forName: "learning"); /* Host requests continue when a reader is closed. */ }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate {
        let store: AppStore
        let course: LoadedCourse
        weak var web: WKWebView?
        
        var markdown: MarkdownArchiveStore { MarkdownArchiveStore(folder:store.records.folder) }
        init(store: AppStore, course: LoadedCourse) { self.store=store;self.course=course }
        func reply(_ id: Int, value: Any = NSNull(), error: String? = nil) {
            let args: [Any] = [id, value, error ?? NSNull() as Any]
            guard let data = try? JSONSerialization.data(withJSONObject: args), let text = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.nativeReply(...\(text))", completionHandler: nil)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "learning", let body = message.body as? [String: Any], let id = body["id"] as? Int, let action = body["action"] as? String else { return }
            let data = body["data"] as? [String: Any] ?? [:]
            do { switch action {
            case "ready":
                let record = try store.session.load(course)
                let pack = try JSONSerialization.data(withJSONObject: course.pack), state = try JSONSerialization.data(withJSONObject: record)
                let p = String(data: pack, encoding: .utf8)!, r = String(data: state, encoding: .utf8)!
                web?.evaluateJavaScript("LearningApp.openPack(\(p),\(r))", completionHandler: nil);reply(id,value:["remembered":KeyStore.exists()])
            case "sessionInfo": reply(id,value:["courseId":course.id,"hasKey":store.session.hasKey])
            case "loadRecords": guard data["courseId"] as? String == course.id else { throw CourseFailure(message: "課程不符") };reply(id,value:try store.session.load(course))
            case "saveRecords": guard let r = data["record"] as? [String: Any], let base = data["base"] as? [String: Any] else { throw CourseFailure(message: "同步格式錯誤") }; reply(id,value:try store.session.save(r,base:base,course:course))
            case "mdStatus": reply(id,value:"MD 自動保存："+(try markdown.target(course.id)).path)
            case "syncMD": reply(id,value:try store.session.syncMarkdown(course))
            case "bindMD": let panel=NSSavePanel();panel.nameFieldStringValue=course.id+"-learning.md";panel.allowedContentTypes=[.init(filenameExtension:"md")!];if panel.runModal() == .OK,let u=panel.url{try markdown.bind(course.id,to:u);_ = try store.session.syncMarkdown(course)};reply(id,value:"已同步："+(try markdown.target(course.id)).path)
            case "showMD": NSWorkspace.shared.open(try markdown.target(course.id));reply(id)
            case "home": store.selected=nil;reply(id)
            case "openFolder": store.chooseFolder();reply(id)
            case "authoring": store.authoring();reply(id)
            case "setKey": let supplied = data["key"] as? String ?? ""; if !supplied.isEmpty { store.session.temporaryKey = supplied }; if data["remember"] as? Bool == true { if !store.session.temporaryKey.isEmpty { try KeyStore.save(store.session.temporaryKey) } } else { if store.session.temporaryKey.isEmpty { store.session.temporaryKey = KeyStore.load() ?? "" };KeyStore.clear() };reply(id)
            case "forgetKey": store.session.temporaryKey="";KeyStore.clear();reply(id)
            case "copy": NSPasteboard.general.clearContents();NSPasteboard.general.setString(data["text"] as? String ?? "",forType:.string);reply(id)
            case "export": let panel=NSSavePanel();panel.nameFieldStringValue=data["name"] as? String ?? "records.json";if panel.runModal() == .OK,let u=panel.url{try (data["text"] as? String ?? "").write(to:u,atomically:true,encoding:.utf8)};reply(id)
            case "import": let panel=NSOpenPanel();panel.allowedContentTypes=[.json];if panel.runModal() == .OK,let u=panel.url {let size=try u.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=10_000_000 else{throw CourseFailure(message:"備份超過 10 MB")};reply(id,value:try String(contentsOf:u,encoding:.utf8))}else{reply(id)}
            case "source": guard let file=data["file"] as? String,(course.model["sources"] as? [[String:Any]] ?? []).contains(where:{$0["file"] as? String == file}) else {throw CourseFailure(message:"來源不在此課程內")};let access=course.root.startAccessingSecurityScopedResource();defer{if access{course.root.stopAccessingSecurityScopedResource()}};let u=try CourseLoader.resource(file,root:course.root);if u.pathExtension.lowercased()=="pdf" {_ = try SourceViewer(url:u,page:Int(data["page"] as? String ?? ""))}else{NSWorkspace.shared.open(u)};reply(id)
            case "cancel": guard let req=data["requestId"] as? String else { throw CourseFailure(message: "問題格式錯誤") }; reply(id,value:try store.session.cancel(course,requestId:req))
            case "ask": guard let requestId=data["requestId"] as? String, let topicId=data["topicId"] as? String, let question=data["question"] as? String else { throw CourseFailure(message: "問題格式錯誤") }; reply(id,value:try store.session.ask(course,topicId:topicId,question:question,requestId:requestId))
            default: throw CourseFailure(message: "不支援的 App 動作")
            }} catch { reply(id,error:error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let u=urlSchemeTask.request.url,u.host=="app",let p=u.path.removingPercentEncoding,CourseLoader.safePath(String(p.dropFirst())) else {urlSchemeTask.didFailWithError(CourseFailure(message:"不安全的資源路徑"));return}
            do {let file=try CourseLoader.resource(String(p.dropFirst()),root:store.resources.appendingPathComponent("Web"));let bytes=try Data(contentsOf:file);let mime=["html":"text/html","js":"text/javascript","css":"text/css","woff2":"font/woff2","woff":"font/woff"][file.pathExtension] ?? "application/octet-stream";urlSchemeTask.didReceive(URLResponse(url:u,mimeType:mime,expectedContentLength:bytes.count,textEncodingName:"utf-8"));urlSchemeTask.didReceive(bytes);urlSchemeTask.didFinish()}catch{urlSchemeTask.didFailWithError(error)}
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { if navigationAction.request.url?.scheme=="learning"{decisionHandler(.allow)}else{if let url=navigationAction.request.url,url.scheme=="https"{NSWorkspace.shared.open(url)};decisionHandler(.cancel)} }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {if let u=navigationAction.request.url,u.scheme=="https"{NSWorkspace.shared.open(u)};return nil}
    }
}

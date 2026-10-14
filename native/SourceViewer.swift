import AppKit
import PDFKit

/// PDFKit page navigation uses the same one-based page sequence as the course.
final class SourceViewer: NSObject, NSWindowDelegate {
    static var viewers: [UUID:SourceViewer] = [:]
    let id=UUID()
    let window: NSWindow
    init(url: URL, page: Int?) throws {
        guard let document=PDFDocument(url:url) else {throw CourseFailure(message:"PDF 無法讀取")}
        let target=(page ?? 1)-1
        guard target>=0,target<document.pageCount,let pdfPage=document.page(at:target) else {throw CourseFailure(message:"來源 PDF 頁序超出範圍")}
        let view=PDFView(frame:NSRect(x:0,y:0,width:900,height:750));view.document=document;view.autoScales=true;view.displayMode = .singlePageContinuous
        window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=url.lastPathComponent;window.contentView=view;window.isReleasedWhenClosed=false
        super.init();window.delegate=self;window.center();window.makeKeyAndOrderFront(nil);view.go(to:pdfPage)
        Self.viewers[id]=self
    }
    func windowWillClose(_ notification: Notification) {Self.viewers.removeValue(forKey:id)}
}

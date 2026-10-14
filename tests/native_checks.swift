import Foundation
import PDFKit
@main struct Checks {
 static func main() throws {
 let root=URL(fileURLWithPath:CommandLine.arguments[1]);let loader=try CourseLoader(webRoot:root.appendingPathComponent("web"))
 let ch3=try loader.load(root.appendingPathComponent("courses/ch3"));let other=try loader.load(root.appendingPathComponent("courses/linear-algebra"))
 precondition(ch3.topicCount==51 && other.topicCount==2)
 let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)}
 var store:RecordStore?=try RecordStore(folder:dir)
 let record:[String:Any]=["format":"learning-records","version":1,"courseId":ch3.id,"notes":["dup":"native round trip"],"qa":[]]
 try store!.save(record);store=nil;store=try RecordStore(folder:dir)
 let restored=try store!.load(ch3.id)
 precondition(restored?["notes"] as? [String:String] == ["dup":"native round trip"])
 do{_ = try CourseLoader.resource("../course.json",root:ch3.root);fatalError("accepted traversal")}catch{}
 precondition(!CourseLoader.safePath("/etc/passwd"))
 let suite="LearningShelf-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
 defer{defaults.removePersistentDomain(forName:suite)}
 let md=MarkdownArchiveStore(folder:dir,defaults:defaults),first=try md.write(ch3.id,text:"教材\n筆記\nQ：test\nA：answer")
 let firstText=try String(contentsOf:first,encoding:.utf8);precondition(firstText.contains("Q：test"))
 _ = try md.write(ch3.id,text:"教材\n筆記\n已刪除 QA")
 let deletedText=try String(contentsOf:first,encoding:.utf8);precondition(!deletedText.contains("Q：test"))
 let chosen=dir.appendingPathComponent("chosen.md");try "initial".write(to:chosen,atomically:true,encoding:.utf8)
 try md.bind(ch3.id,to:chosen);_ = try md.write(ch3.id,text:"bound archive")
 let boundText=try String(contentsOf:chosen,encoding:.utf8);precondition(boundText=="bound archive")
 let reopen=MarkdownArchiveStore(folder:dir,defaults:defaults),reopenedTarget=try reopen.target(ch3.id);precondition(reopenedTarget.resolvingSymlinksInPath()==chosen.resolvingSymlinksInPath())
 let pdf=PDFDocument(url:ch3.root.appendingPathComponent("sources/sp_ch3_2026.pdf"))!
 precondition(pdf.pageCount==73 && pdf.index(for:pdf.page(at:46)!)==46)
 print("Native checks: 51-topic CH3, independent second course, SQLite reopen, path rejection passed.")
 print("MD checks: automatic archive, deleted Q&A exclusion, bound file persistence; PDF page sequence passed.")
 }
}

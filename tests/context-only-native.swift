import Foundation
import JavaScriptCore
@main struct ContextOnlyChecks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),source=URL(fileURLWithPath:CommandLine.arguments[2])
  let loader=try CourseLoader(webRoot:root.appendingPathComponent("web"))
  let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("LearningShelf-context-test-"+UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:dir)}
  let library=try CourseLibrary(dataDirectory:dir),prepared=try library.prepare(source);defer{prepared.discard()}
  let course=try loader.load(prepared.courseRoot);precondition(course.version=="1.0.1" && course.topicCount==24)
  var total=0
  let core=loader.context.objectForKeyedSubscript("CourseCore")!
  for t in course.model["topics"] as! [[String:Any]] {
   let all=t["blocks"] as! [[String:Any]],hidden=all.filter{$0["visibility"] as? String == "contextOnly"}
   let read=core.forProperty("readingBlocks")!.call(withArguments:[t])!.toArray() as! [[String:Any]]
   precondition(read.count==all.count-hidden.count)
   let ctx=core.forProperty("context")!.call(withArguments:[course.model,t,["notes":[:],"qa":[]]])!.toString()!
   for b in hidden{precondition(ctx.contains(b["text"] as! String));precondition(!read.contains{$0["id"] as? String == b["id"] as? String})}
   total += hidden.count
  }
  precondition(total==66)
  var installed:URL?
  try library.install(prepared,courseID:course.id){_,content in installed=content;let reloaded=try loader.load(content);precondition(reloaded.version=="1.0.1")}
  let reopened=try loader.load(installed!);precondition(reopened.id==course.id)
  let report:[String:Any]=["passed":true,"nativeZIPExtractionAndInstallation":source.pathExtension=="zip","nativeCourseLoader":true,"JavaScriptCoreReadingAndContext":true,"hiddenDetails":total,"topics":24,"isolatedTemporaryLibrary":true]
  print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
 }
}

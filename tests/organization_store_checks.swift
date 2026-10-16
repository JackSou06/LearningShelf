import Foundation
import AppKit

@main struct OrganizationStoreChecks {
    @MainActor static func main() async throws {
        func check(_ expression: @autoclosure () throws -> Bool,_ message: String = "",line: UInt = #line) throws {if try !expression(){fatalError("Check failed at \(line): \(message)")}}
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),fixtures=URL(fileURLWithPath:CommandLine.arguments[2])
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("learning-organization-store-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let resources=temp.appendingPathComponent("Resources"),data=temp.appendingPathComponent("data")
        try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true)
        for (source,target) in [("web","Web"),("courses","Courses")] {try FileManager.default.createSymbolicLink(at:resources.appendingPathComponent(target),withDestinationURL:root.appendingPathComponent(source))}
        let store=AppStore(resources:resources,dataDirectory:data,transport:{_,_ in return {}})
        try check(store.entries.count==2 && store.shelf.children(of:nil).count==2,"migrate existing flat catalog")
        func makeFolder(_ name: String) -> String {
            store.createShelfFolder();let id=store.renamingID!;store.renameDraft=name;store.finishShelfRename();return id
        }
        let sp=makeFolder("系統程式設計");store.navigateShelf(sp);let mid=makeFolder("期中範圍");store.navigateShelf(mid)
        let ch3=store.entries.first{$0.id=="sp-ch3-file-io"}!,ch3ID=LibraryOrganization.courseKey(ch3.id)
        store.moveShelfItems([ch3ID],to:mid);store.startShelfRename(ch3ID);store.renameDraft="CH3 我的讀書筆記";store.finishShelfRename()
        store.toggleShelfPins([sp,ch3ID]);try check(store.shelf.node(ch3ID)?.parentID==mid)
        store.undoShelfChange();try check(store.shelf.node(ch3ID)?.pinned==false);store.undoShelfChange(redo:true);try check(store.shelf.node(ch3ID)?.pinned==true)
        let course=try store.loader.load(store.root(ch3));var record=try store.session.load(course)
        record["notes"]=["start":"整理前筆記"];record["qaDrafts"]=["start":"整理前草稿"];record["seen"]=["start"]
        record["answers"]=["model-check:check":["optionId":"a","version":course.version]]
        try store.records.save(record)
        store.open(ch3);try check(store.selected?.id==ch3.id);store.selected=nil
        try check(store.shelf.node(ch3ID)?.name=="CH3 我的讀書筆記" && store.shelf.node(ch3ID)?.parentID==mid,"opening must not overwrite custom names")
        // Native import lands in the current folder and stays at the library.
        await store.importItems([fixtures.appendingPathComponent("root.zip")],confirmReplacement:false)
        let importedID=LibraryOrganization.courseKey("library-import-test")
        try check(store.selected==nil && store.shelf.node(importedID)?.parentID==mid)
        store.startShelfRename(importedID);store.renameDraft="線代補充題";store.finishShelfRename()
        await store.importItems([fixtures.appendingPathComponent("updated.zip")],confirmReplacement:false)
        try check(store.entries.first{$0.id=="library-import-test"}?.version=="1.0.1")
        try check(store.shelf.node(importedID)?.name=="線代補充題" && store.shelf.node(importedID)?.parentID==mid,"update must retain organization")
        // A root drop from inside a folder must not accidentally import into that folder.
        let dropFolder=temp.appendingPathComponent("root-drop-course")
        try FileManager.default.copyItem(at:fixtures.appendingPathComponent("course-v1"),to:dropFolder)
        let manifest=dropFolder.appendingPathComponent("course.json")
        var dropManifest=try JSONSerialization.jsonObject(with:Data(contentsOf:manifest)) as! [String:Any]
        dropManifest["courseId"]="root-drop-test";dropManifest["title"]="根目錄匯入"
        try JSONSerialization.data(withJSONObject:dropManifest).write(to:manifest)
        let provider=NSItemProvider(item:dropFolder as NSURL,typeIdentifier:"public.file-url")
        try check(store.acceptShelfDrop([provider],into:nil))
        for _ in 0..<100 {if store.entries.contains(where:{$0.id=="root-drop-test"}){break};try await Task.sleep(nanoseconds:30_000_000)}
        try check(store.shelf.node(LibraryOrganization.courseKey("root-drop-test"))?.parentID==nil && store.entries.contains(where:{$0.id=="root-drop-test"}),"root file drop must target root")
        store.navigateShelf(sp);store.search="CH3";try check(store.shelfItems.map(\.id)==[ch3ID],"search nested folders")
        store.navigateShelf("root");store.search="線代補充題";store.saveShelfPreferences{$0.searchEverywhere=true};try check(store.shelfItems.contains{$0.id==importedID})
        store.navigateShelf(mid);store.setShelfLayout(.list);store.setShelfSort(.name)
        store.shelfScrollAnchors[mid]=ch3ID;try store.saveShelfViewState()
        let reopened=AppStore(resources:resources,dataDirectory:data)
        try check(reopened.shelfLocation==mid && reopened.shelf.preferences.layout == .list && reopened.shelf.preferences.sort == .name)
        try check(reopened.shelf.preferences.scrollAnchors[mid]==ch3ID)
        try check(reopened.shelf.node(ch3ID)?.name=="CH3 我的讀書筆記")
        // A failed organizational write leaves both visible state and the catalog intact.
        let original=try Data(contentsOf:store.shelfStorage.url),before=store.shelf
        try FileManager.default.removeItem(at:store.shelfStorage.url);try FileManager.default.createDirectory(at:store.shelfStorage.url,withIntermediateDirectories:false)
        store.startShelfRename(ch3ID);store.renameDraft="這個名稱不應被套用";store.finishShelfRename()
        try check(store.shelf==before && store.renamingID==ch3ID)
        try FileManager.default.removeItem(at:store.shelfStorage.url);try original.write(to:store.shelfStorage.url);store.renamingID=nil;store.error=""
        store.trashShelfItems([sp,ch3ID]);try check(store.shelf.node(ch3ID)?.trashRootID==sp)
        let stillThere=try store.records.load(ch3.id)!;try check((stillThere["notes"] as! [String:String])["start"]=="整理前筆記")
        store.navigateShelf("trash");try check(store.shelfItems.map(\.id)==[sp]);store.restoreShelfItems([sp]);try check(store.shelf.node(ch3ID)?.parentID==mid)
        store.trashShelfItems([sp]);await store.permanentlyDeleteShelfItems([sp],includingRecords:false)
        try check(store.shelf.node(sp)==nil && !store.entries.contains{$0.id==ch3.id})
        try check(try store.records.load(ch3.id) != nil,"permanent deletion keeps records by default")
        try check(FileManager.default.fileExists(atPath:root.appendingPathComponent("courses/ch3/course.json").path),"original teaching files remain")
        let afterDelete=AppStore(resources:resources,dataDirectory:data);try check(afterDelete.shelf.node(sp)==nil && !afterDelete.entries.contains{$0.id==ch3.id})
        // Reimport into another folder resumes the same learner records by course ID.
        store.navigateShelf("root");await store.importItems([root.appendingPathComponent("courses/ch3")],confirmReplacement:false)
        try check(store.shelf.node(ch3ID)?.parentID==nil)
        try check((try store.records.load(ch3.id)!["notes"] as! [String:String])["start"]=="整理前筆記")
        print("Organization/AppStore checks passed: catalog migration, folders, aliases, undo/redo, imports/updates, scoped search, restart preferences/scroll, failed-write rollback, recursive trash/restore, permanent purge, original-file protection and record reuse.")
    }
}

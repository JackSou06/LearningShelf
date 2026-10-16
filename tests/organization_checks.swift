import Foundation

@main struct OrganizationChecks {
    static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool, _ message: String = "",line: UInt = #line) throws {if try !value(){fatalError("Check failed at \(line): \(message)")}}
        func rejects(_ label: String,_ operation: () throws -> Void) {do{try operation();fatalError("Accepted invalid operation: "+label)}catch{}}
        var s=LibraryOrganization()
        s.reconcile([(id:"ch3",title:"File I/O"),(id:"ch4",title:"Directories"),(id:"la",title:"Vectors")])
        let c3=LibraryOrganization.courseKey("ch3"),c4=LibraryOrganization.courseKey("ch4"),la=LibraryOrganization.courseKey("la")
        let sp=try s.createFolder("系統程式設計",parent:nil),mid=try s.createFolder("期中範圍",parent:sp),linear=try s.createFolder("線性代數",parent:nil)
        try s.move([c3,c4],to:mid);try s.move([la],to:linear);try s.rename(c3,to:"CH3 筆記")
        try s.validate();try check(s.ancestors(of:c3).map(\.id)==[sp,mid]);try check(s.descendants(of:sp)==[sp,mid,c3,c4])
        rejects("cycle"){try s.move([sp],to:mid)}
        rejects("self parent"){try s.move([sp],to:sp)}
        rejects("course as parent"){try s.move([sp],to:c3)}
        rejects("missing move item"){try s.move(["missing"],to:nil)}
        rejects("empty name"){try s.rename(c3,to:" \n ")}
        rejects("duplicate name"){try s.rename(c4,to:"CH3 筆記")}
        let before=s;rejects("invalid reorder"){try s.move([c3],to:mid,before:la)};try check(before==s)
        try s.move([c4],to:mid,before:c3);try check(s.children(of:mid).map(\.id)==[c4,c3])
        // Opening/reimporting the same course never replaces display names or membership.
        s.reconcile([(id:"ch3",title:"New original title"),(id:"ch4",title:"Directories"),(id:"la",title:"Vectors")],destination:linear)
        try check(s.node(c3)?.name=="CH3 筆記" && s.node(c3)?.parentID==mid)
        try s.togglePins([sp,c3]);try check(s.node(sp)!.pinned && s.node(c3)!.pinned)
        try s.togglePins([sp,c3]);try check(!s.node(sp)!.pinned && !s.node(c3)!.pinned)
        // Selecting a folder and its child moves/trashes each subtree only once.
        try s.trash([sp,c3]);try s.validate();try check(s.nodes.filter{$0.isTrashed}.count==4);try check(s.node(c3)?.trashRootID==sp)
        let collision=try s.createFolder("系統程式設計",parent:nil)
        try check(!collision.isEmpty);try check(try !s.restore([sp]));try s.validate();try check(s.node(sp)?.name=="系統程式設計 (2)")
        try check(s.node(c3)?.parentID==mid && s.node(c3)?.name=="CH3 筆記")
        // Independently deleted descendants keep their own trash group.
        try s.trash([c3]);try s.trash([sp]);try check(s.node(c3)?.trashRootID==c3)
        try check(try s.restore([c3]),"restoring into a trashed parent must fall back to root");try check(s.node(c3)?.parentID==nil)
        let purged=try s.purgeIDs([sp]);try check(purged.contains(c4) && !purged.contains(c3));s.removePermanently(purged);try s.validate()
        rejects("purge live item"){_ = try s.purgeIDs([c3])}
        // Same names moved from different parents remain distinct.
        let a=try s.createFolder("課題",parent:linear),b=try s.createFolder("課題",parent:nil)
        try s.move([a],to:nil);try check(s.node(a)?.name=="課題 (2)" && s.node(b)?.name=="課題")
        var corrupt=s;corrupt.nodes.append(s.nodes[0]);rejects("duplicate IDs"){try corrupt.validate()}
        var cycle=s;let i=cycle.nodes.firstIndex{$0.id==linear}!;cycle.nodes[i].parentID=linear;rejects("stored cycle"){try cycle.validate()}
        var batch=LibraryOrganization()
        batch.reconcile([(id:"nested",title:"課題")])
        let batchFolder=try batch.createFolder("課程",parent:nil),nested=LibraryOrganization.courseKey("nested")
        try batch.move([nested],to:batchFolder);try batch.trash([nested]);try batch.trash([batchFolder])
        try check(try !batch.restore([batchFolder,nested]),"batch restoration restores ancestors before children")
        try check(batch.node(nested)?.parentID==batchFolder);try batch.validate()
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("library-organization-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let disk=LibraryOrganizationStore(directory:folder);s.preferences.location=linear;s.preferences.layout = .list;s.preferences.sort = .name
        try disk.save(s);try check(try disk.load()==s,"reopen must retain all organization and UI preferences")
        let raw=try Data(contentsOf:disk.url)
        try FileManager.default.removeItem(at:disk.url);try FileManager.default.createDirectory(at:disk.url,withIntermediateDirectories:false)
        rejects("atomic write failure"){try disk.save(s)}
        try FileManager.default.removeItem(at:disk.url);try raw.write(to:disk.url)
        var unknownVersion=s;unknownVersion.version=99;rejects("future version"){try disk.save(unknownVersion)}
        try check(try Data(contentsOf:disk.url)==raw,"failed validation must not overwrite existing data")
        print("Organization checks passed: hierarchy, cycle rejection, names, batch moves, reorder, update preservation, pins, recursive trash/restore, orphan fallback, purge boundaries, persisted preferences and atomic failure.")
    }
}

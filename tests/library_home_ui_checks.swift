import SwiftUI
import AppKit

/// Runs the real SwiftUI home in a temporary native window with an isolated catalog.
@main struct LibraryHomeUIChecks {
    @MainActor static func main() throws {
        func check(_ condition: @autoclosure () -> Bool,_ message: String) {if !condition(){fatalError(message)}}
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("learningshelf-native-ui-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:temp)}
        let resources=temp.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true)
        for (source,target) in [("web","Web"),("courses","Courses")] {try FileManager.default.createSymbolicLink(at:resources.appendingPathComponent(target),withDestinationURL:root.appendingPathComponent(source))}
        let app=NSApplication.shared;app.setActivationPolicy(.regular);app.finishLaunching()
        let store=AppStore(resources:resources,dataDirectory:temp.appendingPathComponent("data"),transport:{_,_ in return {}})
        let hosting=NSHostingView(rootView:CourseHome(store:store,updater:AppUpdater()))
        let window=NSWindow(contentRect:NSRect(x:180,y:140,width:1100,height:820),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="LearningShelf 教材庫介面檢查";window.isReleasedWhenClosed=false;window.contentView=hosting;window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        defer{window.orderOut(nil);window.close()}
        func pump(_ seconds: Double = 0.25) {
            let end=Date().addingTimeInterval(seconds)
            while Date()<end {
                if let event=app.nextEvent(matching:.any,until:Date().addingTimeInterval(0.02),inMode:.default,dequeue:true){app.sendEvent(event)}
                RunLoop.current.run(until:Date().addingTimeInterval(0.005))
            }
            hosting.layoutSubtreeIfNeeded();hosting.displayIfNeeded()
        }
        func key(_ code: UInt16,_ characters: String,flags: NSEvent.ModifierFlags = []) {
            let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:(window.attachedSheet ?? window).windowNumber,context:nil,characters:characters,charactersIgnoringModifiers:characters,isARepeat:false,keyCode:code)!
            app.postEvent(event,atStart:false);pump()
        }
        func screenshot(_ name: String) throws {
            pump(0.4)
            let capture = name == "move-sheet" ? (window.attachedSheet?.contentView ?? hosting) : hosting
            guard let image=capture.bitmapImageRepForCachingDisplay(in:capture.bounds) else{fatalError("No native bitmap")}
            capture.cacheDisplay(in:capture.bounds,to:image)
            guard let data=image.representation(using:.png,properties:[:]) else{fatalError("No native PNG")}
            try data.write(to:output.appendingPathComponent(name+".png"))
        }
        pump(0.7)
        try screenshot("home-before-folders")
        window.makeFirstResponder(hosting);key(45,"n",flags:[.command,.shift]);check(store.renamingID != nil,"New folder button must start editing")
        let sp=store.renamingID!;store.renameDraft="系統程式設計";key(36,"\r")
        check(store.renamingID==nil && store.shelf.node(sp)?.name=="系統程式設計","Return must commit inline rename")
        window.makeFirstResponder(hosting);key(31,"o",flags:.command);check(store.shelfLocation==sp,"Folder open button must navigate")
        window.makeFirstResponder(hosting);key(45,"n",flags:[.command,.shift]);let mid=store.renamingID!;store.renameDraft="期中範圍";key(36,"\r")
        let ch3=LibraryOrganization.courseKey("sp-ch3-file-io"),linear=LibraryOrganization.courseKey("example-linear-algebra")
        store.moveShelfItems([ch3],to:mid);store.navigateShelf("root");pump()
        // Exercise the same native item-provider transport used by drag and drop.
        let provider=store.shelfDragProvider(store.shelf.node(linear)!)
        check(store.acceptShelfDrop([provider],into:sp),"Internal drag payload should be accepted");pump(0.5)
        check(store.shelf.node(linear)?.parentID==sp,"Drop must move the actual selected item")
        store.shelfSelection=[sp];window.makeFirstResponder(hosting);key(51,"\u{7f}",flags:.command)
        check(store.shelf.node(sp)?.isTrashed==true,"Command-delete must move selected folder to trash")
        key(6,"z",flags:.command);check(store.shelf.node(sp)?.isTrashed==false,"Command-Z must undo the trash action")
        store.navigateShelf(mid);store.shelfSelection=[ch3];pump();store.showShelfMove(store.shelfSelection);pump()
        check(store.showsMoveSheet && window.attachedSheet != nil,"Move action must present the native sheet");pump(0.4);try screenshot("move-sheet");key(53,"\u{1b}");check(!store.showsMoveSheet,"Move cancellation")
        store.navigateShelf("root");store.toggleShelfPins([sp]);store.shelfNotice="";pump();try screenshot("library-home")
        store.navigateShelf(sp);store.shelfNotice="";pump();try screenshot("course-folder")
        store.setShelfLayout(.list);store.navigateShelf("all");store.shelfNotice="";pump();try screenshot("library-list")
        store.setShelfLayout(.cards);store.navigateShelf("root");window.setContentSize(NSSize(width:760,height:580));pump(0.5);try screenshot("library-compact")
        check(hosting.bounds.width>=750,"Compact native window must render")
        window.setContentSize(NSSize(width:1100,height:820));window.appearance=NSAppearance(named:.aqua);hosting.appearance=NSAppearance(named:.aqua)
        store.navigateShelf(sp);pump(0.5);try screenshot("course-folder-light")
        print("Native home UI checks passed: real SwiftUI rendering, native keyboard new/open actions, inline Return rename, native drag payload, Command-delete, Command-Z, modal cancellation, cards/list and 760px layout. Screenshots: "+output.path)
    }
}

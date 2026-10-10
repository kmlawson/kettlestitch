import AppKit
import CropCore

extension AppDelegate: NSMenuItemValidation, NSMenuDelegate {
    /// The menu commands this delegate handles. Enabling, titles and check marks all come from `MenuPolicy`.
    static let commands: [Selector:MenuCommand] = [
        #selector(newProject):.newProject,#selector(openProject):.openProject,#selector(importImages):.importPhotographs,#selector(locatePhotographs):.locatePhotographs,#selector(saveProject):.save,#selector(saveAs):.saveAs,#selector(exportImages):.export,#selector(showSettings):.settings,#selector(help):.help,
        #selector(undo):.undo,#selector(redo):.redo,#selector(copySettings):.copySettings,#selector(pasteSettings):.pasteSettings,#selector(applySettingsToAll):.applySettingsToAll,#selector(resetAdjustments):.resetAdjustments,
        #selector(next):.nextPage,#selector(previous):.previousPage,#selector(firstPage):.firstPage,#selector(lastPage):.lastPage,#selector(nextReview):.nextUnreviewed,#selector(nextFlagged):.nextFlagged,#selector(accept):.accept,
        #selector(selectAllPages):.selectAllPages,#selector(toggleFlag):.flag,#selector(reversePages):.reversePages,#selector(removePages):.removePages,#selector(rotateLeft):.rotateLeft,#selector(rotate):.rotateRight,
        #selector(detectCurrent):.detect,#selector(detectPending):.detectPending,#selector(nextCandidate):.nextProposal,#selector(previousCandidate):.previousProposal,#selector(resetCrop):.fullImage,#selector(copyPrevious):.copyPreviousCrop,
        #selector(proposeSplit):.proposeSplit,#selector(removeSplit):.removeSplit,#selector(moveSplitLeft):.moveSplitLeft,#selector(moveSplitRight):.moveSplitRight,#selector(sendToClaude):.sendToClaude,#selector(stop):.stop,
        #selector(deskew):.deskew,#selector(removeDeskew):.removeDeskew,#selector(deskewClockwise):.deskewClockwise,#selector(deskewCounterclockwise):.deskewCounterclockwise,#selector(addZone):.addPictureZone,#selector(removeZones):.removePictureZones,#selector(showDeviations):.showDeviations,#selector(nextOutlier):.nextOutlier,
        #selector(togglePreview):.preview,#selector(zoomIn):.zoomIn,#selector(zoomOut):.zoomOut,#selector(fit):.zoomToFit,#selector(toggleSidebarPane):.toggleSidebar,#selector(toggleInspector):.toggleInspector]
    /// The field editor of whichever window has the keyboard, while a text field is being edited.
    var editedText: NSTextView? {(NSApp.keyWindow ?? window)?.firstResponder as? NSTextView}
    var menuState: MenuState {
        var s=MenuState();let targets=targetIndexes,page=current.map{project.pages[$0]}
        s.pageCount=project.pages.count;s.current=current;s.targetCount=targets.count
        s.canUndo = !undoStack.isEmpty || adjusting;s.canRedo = !redoStack.isEmpty
        s.editingText=editedText != nil;s.textCanUndo=editedText?.undoManager?.canUndo ?? false;s.textCanRedo=editedText?.undoManager?.canRedo ?? false
        s.hasCopiedSettings=copiedSettings != nil;s.targetsHaveAdjustments=targets.contains{project.pages[$0].adjustments != nil}
        s.proposalCount=page?.candidates.count ?? 0
        s.pendingCount=project.pages.filter{$0.status=="Pending"}.count;s.unreviewedCount=project.pages.filter{!$0.reviewed}.count;s.flaggedCount=project.pages.filter{$0.flagged==true}.count
        s.currentFlagged=page?.flagged==true;s.currentHasSplit=page?.split != nil;s.targetsHaveSplit=targets.contains{project.pages[$0].split != nil}
        s.targetsHaveDeskew=targets.contains{project.pages[$0].deskew != nil};s.targetsHaveZones=targets.contains{project.pages[$0].pictureZones != nil};s.outlierCount=deviationRows.filter{$0.isOutlier}.count
        s.detecting=detecting;s.exporting=exporting;s.reviewing=reviewing;s.previewing=canvas.preview
        s.windowActive=window.attachedSheet==nil && (NSApp.keyWindow==nil || NSApp.keyWindow===window)
        s.sidebarVisible = !sidebarItem.isCollapsed;s.inspectorVisible = !inspectorItem.isCollapsed
        return s
    }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        guard let action=item.action,let command=AppDelegate.commands[action] else{return true}
        let state=menuState
        if let title=MenuPolicy.title(command,state){item.title=title}
        item.state=MenuPolicy.isChecked(command,state) ? .on:.off
        return MenuPolicy.isEnabled(command,state)
    }
    @objc func toggleSidebarPane(){split.toggleSidebar(nil)}

    func buildMenus(){
        let main=NSMenu()
        func menu(_ title:String)->NSMenu {let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let sub=NSMenu(title:title);item.submenu=sub;main.addItem(item);return sub}
        @discardableResult func add(_ menu:NSMenu,_ title:String,_ action:Selector?,_ key:String="",_ modifiers:NSEvent.ModifierFlags=[.command],icon:String?=nil,own:Bool=true)->NSMenuItem {
            let item=menu.addItem(withTitle:title,action:action,keyEquivalent:key);item.keyEquivalentModifierMask=modifiers
            if own {item.target=self}
            if let icon {item.image=symbol(icon)}
            return item
        }
        func arrow(_ key:Int)->String {String(UnicodeScalar(key)!)}
        let app=menu("KettleStitch")
        add(app,"About KettleStitch",#selector(NSApplication.orderFrontStandardAboutPanel(_:)),own:false)
        app.addItem(.separator());add(app,"Settings…",#selector(showSettings),",")
        app.addItem(.separator());add(app,"Hide KettleStitch",#selector(NSApplication.hide(_:)),"h",own:false)
        add(app,"Hide Others",#selector(NSApplication.hideOtherApplications(_:)),"h",[.command,.option],own:false);add(app,"Show All",#selector(NSApplication.unhideAllApplications(_:)),own:false)
        app.addItem(.separator());add(app,"Quit KettleStitch",#selector(NSApplication.terminate(_:)),"q",own:false)

        let file=menu("File")
        add(file,"New Project…",#selector(newProject),"n");add(file,"Open Project…",#selector(openProject),"o")
        let recent=NSMenu(title:"Open Recent");recent.delegate=self;add(file,"Open Recent",nil,own:false).submenu=recent
        file.addItem(.separator());add(file,"Import Photographs…",#selector(importImages),"i");add(file,"Locate Missing Photographs…",#selector(locatePhotographs))
        file.addItem(.separator());add(file,"Close",#selector(NSWindow.performClose(_:)),"w",own:false);add(file,"Save",#selector(saveProject),"s");add(file,"Save Project As…",#selector(saveAs),"s",[.command,.shift])
        file.addItem(.separator());add(file,"Export…",#selector(exportImages),"e")

        let edit=menu("Edit")
        add(edit,"Undo",#selector(undo),"z");add(edit,"Redo",#selector(redo),"z",[.command,.shift])
        let legacy=add(edit,"Redo",#selector(redo),"y");legacy.isHidden=true;legacy.allowsKeyEquivalentWhenHidden=true
        edit.addItem(.separator())
        add(edit,"Cut",#selector(NSText.cut(_:)),"x",own:false);add(edit,"Copy",#selector(NSText.copy(_:)),"c",own:false);add(edit,"Paste",#selector(NSText.paste(_:)),"v",own:false);add(edit,"Select All",#selector(NSText.selectAll(_:)),"a",own:false)
        edit.addItem(.separator())
        add(edit,"Copy Settings",#selector(copySettings),"c",[.command,.shift]);add(edit,"Paste Settings",#selector(pasteSettings),"v",[.command,.shift])
        add(edit,"Apply Settings to All Pages",#selector(applySettingsToAll));add(edit,"Reset Image Adjustments",#selector(resetAdjustments))

        let page=menu("Page")
        add(page,"Next Page",#selector(next),"]");add(page,"Previous Page",#selector(previous),"[")
        let go=NSMenu(title:"Go To");add(page,"Go To",nil,own:false).submenu=go
        add(go,"First Page",#selector(firstPage),arrow(NSUpArrowFunctionKey));add(go,"Last Page",#selector(lastPage),arrow(NSDownArrowFunctionKey))
        go.addItem(.separator());add(go,"Next Unreviewed",#selector(nextReview),"u");add(go,"Next Flagged",#selector(nextFlagged),"u",[.command,.shift]);add(go,"Next Unusual Page",#selector(nextOutlier),"u",[.command,.option])
        add(page,"Accept and Next",#selector(accept),"\r")
        page.addItem(.separator())
        add(page,"Select All Pages",#selector(selectAllPages),"a",[.command,.shift]);add(page,"Add Flag",#selector(toggleFlag),"l",[.command,.shift])
        page.addItem(.separator())
        add(page,"Rotate Left",#selector(rotateLeft),"l");add(page,"Rotate Right",#selector(rotate),"r")
        page.addItem(.separator())
        add(page,"Reverse Pages Order",#selector(reversePages));add(page,"Remove from Project",#selector(removePages),"\u{8}")

        let crop=menu("Crop")
        add(crop,"Detect Cropping Frame",#selector(detectCurrent),"d",[.command,.shift]);add(crop,"Detect All Pending Pages",#selector(detectPending),"d",[.command,.option])
        add(crop,"Next Proposal",#selector(nextCandidate),"]",[.command,.option]);add(crop,"Previous Proposal",#selector(previousCandidate),"[",[.command,.option])
        crop.addItem(.separator())
        add(crop,"Set Cropping Frame to Full Image",#selector(resetCrop));add(crop,"Copy Previous Cropping Frame",#selector(copyPrevious))
        crop.addItem(.separator())
        add(crop,"Propose Page Split",#selector(proposeSplit),"t");add(crop,"Remove Page Split",#selector(removeSplit),"t",[.command,.shift])
        add(crop,"Move Split Left",#selector(moveSplitLeft),arrow(NSLeftArrowFunctionKey),[.command,.option]);add(crop,"Move Split Right",#selector(moveSplitRight),arrow(NSRightArrowFunctionKey),[.command,.option])
        crop.addItem(.separator())
        add(crop,"Deskew",#selector(deskew),"k");add(crop,"Remove Deskew",#selector(removeDeskew),"k",[.command,.shift])
        add(crop,"Turn Counterclockwise by 0.1°",#selector(deskewCounterclockwise),"[",[.command,.control]);add(crop,"Turn Clockwise by 0.1°",#selector(deskewClockwise),"]",[.command,.control])
        crop.addItem(.separator())
        add(crop,"Add Picture Zone",#selector(addZone),"p",[.command,.option]);add(crop,"Remove Picture Zones",#selector(removeZones))
        crop.addItem(.separator())
        add(crop,"Send to Claude",#selector(sendToClaude),"c",[.command,.option]);add(crop,"Claude Usage Log…",#selector(showUsageLog))
        crop.addItem(.separator())
        add(crop,"Stop Background Work",#selector(stop),".")

        let view=menu("View")
        add(view,"Corrected Preview",#selector(togglePreview),"p",[.command,.shift])
        view.addItem(.separator());add(view,"Zoom In",#selector(zoomIn),"+");add(view,"Zoom Out",#selector(zoomOut),"-");add(view,"Zoom to Fit",#selector(fit),"0")
        view.addItem(.separator());add(view,"Show Deviations",#selector(showDeviations),"j")
        view.addItem(.separator());add(view,"Show Sidebar",#selector(toggleSidebarPane),"s",[.command,.control]);add(view,"Show Inspector",#selector(toggleInspector),"i",[.command,.option])
        view.addItem(.separator());add(view,"Enter Full Screen",#selector(NSWindow.toggleFullScreen(_:)),"f",[.command,.control],own:false)

        let windows=menu("Window")
        add(windows,"Minimize",#selector(NSWindow.performMiniaturize(_:)),"m",own:false);add(windows,"Zoom",#selector(NSWindow.performZoom(_:)),own:false)
        windows.addItem(.separator());add(windows,"Bring All to Front",#selector(NSApplication.arrangeInFront(_:)),own:false)
        let help=menu("Help");add(help,"KettleStitch Keyboard Shortcuts",#selector(self.help),"?")
        NSApp.mainMenu=main;NSApp.windowsMenu=windows;NSApp.helpMenu=help
    }
    /// Rebuilds Open Recent from the system's list each time it opens.
    func menuNeedsUpdate(_ menu:NSMenu){
        menu.removeAllItems()
        let urls=NSDocumentController.shared.recentDocumentURLs.filter{FileManager.default.fileExists(atPath:$0.path)}
        for url in urls {let item=menu.addItem(withTitle:url.deletingPathExtension().lastPathComponent,action:#selector(openRecent(_:)),keyEquivalent:"");item.target=self;item.representedObject=url;item.toolTip=url.path}
        if urls.isEmpty {menu.addItem(withTitle:"No Recent Projects",action:nil,keyEquivalent:"")}
        else {menu.addItem(.separator());menu.addItem(withTitle:"Clear Menu",action:#selector(NSDocumentController.clearRecentDocuments(_:)),keyEquivalent:"").target=NSDocumentController.shared}
    }
}

/// The history of requests to Claude: when each was made, how long it took and what it cost in tokens.
final class UsageLogController: NSObject {
    let window=NSPanel(contentRect:NSRect(x:0,y:0,width:760,height:420),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
    let text=NSTextView()
    let url:URL
    init(url:URL){
        self.url=url;super.init()
        window.title="Claude Usage Log";window.isReleasedWhenClosed=false;window.isFloatingPanel=false;window.hidesOnDeactivate=false;window.minSize=NSSize(width:480,height:200)
        text.isEditable=false;text.font = .monospacedSystemFont(ofSize:12,weight:.regular);text.textContainerInset=NSSize(width:12,height:12);text.autoresizingMask=[.width]
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.documentView=text
        window.contentView=scroll;window.center()
    }
    func reload(){text.string=UsageLog.text(UsageLog.read(url))}
    func show(){reload();window.makeKeyAndOrderFront(nil)}
}
/// The keyboard reference, laid out from `ShortcutReference`.
final class ShortcutsController: NSObject {
    let window=NSPanel(contentRect:NSRect(x:0,y:0,width:560,height:640),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
    private final class Flipped: NSView {override var isFlipped:Bool{true}}
    override init(){
        super.init()
        window.title="KettleStitch Keyboard Shortcuts";window.isReleasedWhenClosed=false;window.isFloatingPanel=false;window.hidesOnDeactivate=false;window.minSize=NSSize(width:460,height:320)
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=6;stack.translatesAutoresizingMaskIntoConstraints=false
        for section in ShortcutReference.sections {
            let title=NSTextField(labelWithString:section.title.uppercased());title.font = .systemFont(ofSize:11,weight:.semibold);title.textColor = .secondaryLabelColor
            let rows=section.entries.map{entry->[NSView] in
                let keys=NSTextField(labelWithString:entry.keys);keys.font = .monospacedSystemFont(ofSize:12,weight:.medium);keys.alignment = .right
                let action=NSTextField(wrappingLabelWithString:entry.action);action.font = .systemFont(ofSize:13);action.preferredMaxLayoutWidth=330
                return [keys,action]
            }
            let grid=NSGridView(views:rows);grid.rowSpacing=5;grid.columnSpacing=14;grid.column(at:0).xPlacement = .trailing;grid.column(at:0).width=150
            stack.addArrangedSubview(title);stack.addArrangedSubview(grid);stack.setCustomSpacing(18,after:grid)
        }
        let notes=NSTextField(wrappingLabelWithString:ShortcutReference.notes);notes.font = .systemFont(ofSize:11);notes.textColor = .secondaryLabelColor;notes.preferredMaxLayoutWidth=500
        stack.addArrangedSubview(notes)
        let document=Flipped();document.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.documentView=document
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:document.topAnchor,constant:20),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:24),stack.trailingAnchor.constraint(lessThanOrEqualTo:document.trailingAnchor,constant:-24),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-20),
            document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor)])
        window.contentView=scroll;window.center()
    }
    func show(){window.makeKeyAndOrderFront(nil)}
}

/// Lists every page with how unusual its crop is; click a column to sort by it, a row to go to that page.
final class DeviationsController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window=NSPanel(contentRect:NSRect(x:0,y:0,width:520,height:460),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
    let table=NSTableView()
    weak var owner: AppDelegate?
    var rows: [DeviationRow]=[]
    var metric=Deviation.Metric.worst
    var descending=true
    static let columns:[(id:String,title:String,metric:Deviation.Metric,width:CGFloat)]=[("page","Page",.page,190),("worst","Most",.worst,58),("size","Size",.size,58),("shape","Shape",.shape,58),("taper","Taper",.taper,58),("skew","Skew",.skew,58)]
    init(owner:AppDelegate){
        self.owner=owner;super.init()
        window.title="Deviations";window.isReleasedWhenClosed=false;window.isFloatingPanel=false;window.hidesOnDeactivate=false;window.minSize=NSSize(width:420,height:240)
        for column in DeviationsController.columns {
            let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(column.id));c.title=column.title;c.width=column.width;c.minWidth=44
            c.sortDescriptorPrototype=NSSortDescriptor(key:column.id,ascending:column.id=="page")
            c.headerToolTip=column.id=="page" ? "Page order":"How far this measure is from what is usual in the project; \(Int(Deviation.threshold)).5 or more is marked unusual"
            table.addTableColumn(c)
        }
        table.dataSource=self;table.delegate=self;table.usesAlternatingRowBackgroundColors=true;table.rowHeight=20;table.allowsMultipleSelection=false;table.target=self;table.action=#selector(rowClicked)
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.documentView=table
        window.contentView=scroll;window.center()
    }
    func show(){refresh();window.makeKeyAndOrderFront(nil)}
    func refresh(){
        guard let owner,window.isVisible || rows.isEmpty else{return}
        rows=Deviation.sorted(owner.deviationRows,by:metric,descending:descending);table.reloadData()
    }
    func numberOfRows(in tableView:NSTableView)->Int {rows.count}
    func tableView(_ tableView:NSTableView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]){
        guard let first=tableView.sortDescriptors.first,let column=DeviationsController.columns.first(where:{$0.id==first.key}) else{return}
        metric=column.metric;descending = !first.ascending;refresh()
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard let owner,let id=tableColumn?.identifier.rawValue,rows.indices.contains(row) else{return nil}
        let r=rows[row]
        let label=NSTextField(labelWithString:"");label.lineBreakMode = .byTruncatingMiddle;label.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular)
        func score(_ v:Double){label.stringValue=v<0.05 ? "–":String(format:"%.1f",v);label.alignment = .right;label.textColor=v>=Deviation.threshold ? .systemOrange:.labelColor}
        switch id {
        case "page":
            let name=owner.project.pages.indices.contains(r.index) ? URL(fileURLWithPath:owner.project.pages[r.index].path).lastPathComponent:""
            label.stringValue="\(r.index+1). \(name)"+(r.reason.map{"  ⚠︎ "+$0} ?? "")
        case "worst":score(r.worst);case "size":score(r.size);case "shape":score(r.shape);case "taper":score(r.taper);default:score(r.skew)
        }
        return label
    }
    @objc func rowClicked(){if rows.indices.contains(table.clickedRow){owner?.show(rows[table.clickedRow].index)}}
}

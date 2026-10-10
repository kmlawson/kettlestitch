import AppKit
import CropCore
import UniformTypeIdentifiers

/// Page snapshots restore edits; a structure snapshot restores the whole page list after reordering or removal.
enum UndoEntry {case pages([Page]);case structure([Page],Int)}

func symbol(_ names:String...)->NSImage? {
    for name in names {if let image=NSImage(systemSymbolName:name,accessibilityDescription:nil){return image}}
    return nil
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    let canvas=CropCanvas()
    let table=PageTable()
    let status=NSTextField(labelWithString:"Open photographs to begin")
    let counter=NSTextField(labelWithString:"")
    let progress=NSProgressIndicator()
    let stopButton=NSButton()
    let detail=NSTextField(wrappingLabelWithString:"")
    let note=NSTextField(wrappingLabelWithString:"")
    let candidates=NSPopUpButton()
    let cleanupControl=NSSegmentedControl()
    let cleanupName=NSTextField(labelWithString:"")
    let brightnessSlider=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    let contrastSlider=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    let widthField=NSTextField()
    let heightField=NSTextField()
    let fitPopup=NSPopUpButton()
    let resolutionLabel=NSTextField(labelWithString:"")
    var inspectorControls:[NSControl]=[]
    let split=NSSplitViewController()
    var sidebarItem: NSSplitViewItem!
    var inspectorItem: NSSplitViewItem!
    var previewItem: NSToolbarItemGroup?
    let queue=OperationQueue()
    let displayQueue=OperationQueue()
    let exportQueue=OperationQueue()
    let thumbnailQueue=OperationQueue()
    let reviewQueue=OperationQueue()
    let splitQueue=OperationQueue()
    let despeckleControl=NSSegmentedControl()
    var deviations: DeviationsController?
    var deviationCache: [DeviationRow]?
    /// How each page's crop compares with the rest; recomputed after any change.
    var deviationRows: [DeviationRow] {if deviationCache==nil {deviationCache=Deviation.report(project.pages)};return deviationCache!}
    let testDirectory=ProcessInfo.processInfo.environment["KETTLESTITCH_TEST_DIR"]
    var project=Project()
    var projectURL: URL!
    var generation=UUID()
    var displayToken=UUID()
    var original: CGImage?
    var undoStack: [UndoEntry]=[]
    var redoStack: [UndoEntry]=[]
    var detecting=false
    var exportCancelled=false
    var exporting=false
    var reviewing=false
    var reviewCancelled=false
    var reviewProcess: Process?
    var tracker=ProgressTracker()
    var notedRecent: URL?
    /// Files handed over before the window exists, as when the app is started by dropping them on its icon.
    var pendingOpen: [URL]=[]
    /// Pages sent in the current batch that Claude has not answered yet, and the one it is looking at now.
    var reviewPending=Set<UUID>()
    var reviewActive: UUID?
    var reviewTimer: Timer?
    var reviewStarted=Date()
    var reviewModel=""
    var reviewTotal=0
    var reviewNumber=0
    var adjusting=false
    var reloading=false
    var shownSize=(width:0.0,height:0.0)
    var copiedSettings: (Adjustments?,PageFormat?)?
    var pixelSizes: [String:CGSize]=[:]
    var exportOptions=ExportOptions()
    var exportSheet: ExportSheetController?
    var settings: SettingsController?
    var shortcuts: ShortcutsController?
    var shortcutMonitor: Any?
    var thumbs=NSCache<NSString,NSImage>()
    var thumbnailPending=Set<String>()
    var current: Int? {project.pages.indices.contains(project.selected) ? project.selected:nil}
    /// Pages a settings change applies to: the sidebar selection when it includes the photograph on screen.
    var targetIndexes: [Int] {
        guard let i=current else{return []}
        let rows=table.selectedRowIndexes.filter{project.pages.indices.contains($0)}
        return rows.contains(i) ? Array(rows):[i]
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.maxConcurrentOperationCount=1;queue.qualityOfService = .utility
        displayQueue.maxConcurrentOperationCount=1;displayQueue.qualityOfService = .userInitiated
        exportQueue.maxConcurrentOperationCount=1
        reviewQueue.maxConcurrentOperationCount=1;reviewQueue.qualityOfService = .utility
        splitQueue.maxConcurrentOperationCount=1;splitQueue.qualityOfService = .userInitiated
        thumbnailQueue.maxConcurrentOperationCount=1;thumbnailQueue.qualityOfService = .utility
        thumbs.totalCostLimit=24*1024*1024
        let library=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        let support=testDirectory.map{URL(fileURLWithPath:$0)} ?? library.appendingPathComponent("KettleStitch")
        if testDirectory == nil {carryOverLegacyData(in:library,to:support)}
        do {try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)} catch {showError(error)}
        // The app opens empty. Each session gets its own untitled file, so unnamed work from an earlier
        // session is never overwritten; it stays reachable under File ▸ Open Recent.
        projectURL=support.appendingPathComponent(LaunchPolicy.untitledName(Date()))
        if let asked=LaunchPolicy.projectToOpen(arguments:CommandLine.arguments,testDirectory:testDirectory),FileManager.default.fileExists(atPath:asked.path) {
            do {project=try Project.read(asked);project.selected=min(max(0,project.selected),max(0,project.pages.count-1));projectURL=asked} catch {showError(error)}
        }
        if let data=UserDefaults.standard.data(forKey:"exportOptions"),let saved=try? JSONDecoder().decode(ExportOptions.self,from:data) {exportOptions=saved}
        buildUI();buildMenus();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        canvas.onCommit={[weak self] q in self?.edit{$0.setManualCrop(q)}}
        canvas.onSplitCommit={[weak self] s in self?.edit(geometry:false){$0.split=s}}
        canvas.onZoneCommit={[weak self] z in self?.edit(geometry:false){$0.pictureZones=($0.pictureZones ?? [])+[z]};self?.zoneDrawn()}
        canvas.onZoneRemove={[weak self] i in self?.edit(geometry:false){$0.pictureZones?.remove(at:i);if $0.pictureZones?.isEmpty==true{$0.pictureZones=nil}}}
        canvas.onNavigate={[weak self] delta in self?.navigate(delta)}
        canvas.onAccept={[weak self] in self?.accept()}
        canvas.onUndo={[weak self] in self?.undo()}
        shortcutMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self, NSApp.keyWindow===self.window, !(self.window.firstResponder is NSTextView), !(self.window.firstResponder is NSTextField) else {return event}
            return self.handleKey(event) ? nil:event
        }
        reloadPages();selectCurrent();updateTitle()
        status.stringValue=project.pages.isEmpty ? "Drop photographs here, or choose File ▸ Import Photographs":"Press ? for keyboard shortcuts"
        window.delegate=self;window.registerForDraggedTypes([.fileURL])
        let waiting=pendingOpen;pendingOpen=[];if !waiting.isEmpty {receive(waiting)}
        // Test hook for files handed over by the system at launch: report what arrived, then quit.
        if testDirectory != nil,let report=ProcessInfo.processInfo.environment["KETTLESTITCH_REPORT"] {
            DispatchQueue.main.asyncAfter(deadline:.now()+2){
                try? "pages=\(self.project.pages.count) title=\(self.window.title)\n".write(toFile:report,atomically:true,encoding:.utf8);NSApp.terminate(nil)
            }
        }
        if let folder=ProcessInfo.processInfo.environment["KETTLESTITCH_SMOKE_FOLDER"],let other=ProcessInfo.processInfo.environment["KETTLESTITCH_SMOKE_PROJECT"],let dir=testDirectory {runEmptySmoke(dir,folder:URL(fileURLWithPath:folder),project:URL(fileURLWithPath:other))}
        if CommandLine.arguments.contains("--smoke"),let dir=testDirectory {runSmoke(dir)}
    }
    /// Moves sessions saved under an earlier name into place and copies its preferences, unless this name already has its own.
    func carryOverLegacyData(in library:URL,to new:URL){
        let files=FileManager.default
        if let folder=LegacyNames.firstExisting(LegacyNames.supportFolders,where:{files.fileExists(atPath:library.appendingPathComponent($0).path)}),
           LegacyNames.shouldCarryOver(oldExists:true,newExists:files.fileExists(atPath:new.path)) {try? files.moveItem(at:library.appendingPathComponent(folder),to:new)}
        let defaults=UserDefaults.standard
        if let domain=LegacyNames.firstExisting(LegacyNames.preferencesDomains,where:{!(defaults.persistentDomain(forName:$0) ?? [:]).isEmpty}),
           LegacyNames.shouldCarryOver(oldExists:true,newExists:defaults.object(forKey:"legacyPreferencesCopied") != nil) {
            let earlier=defaults.persistentDomain(forName:domain) ?? [:]
            for key in ["exportOptions","claudeModel"] {if let value=earlier[key],defaults.object(forKey:key)==nil {defaults.set(value,forKey:key)}}
            defaults.set(true,forKey:"legacyPreferencesCopied")
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification: Notification){queue.cancelAllOperations();reviewProcess?.terminate();save()}

    // MARK: Page list
    func numberOfRows(in tableView:NSTableView)->Int {project.pages.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let p=project.pages[row]
        let cell=(tableView.makeView(withIdentifier:PageCell.identifier,owner:nil) as? PageCell) ?? PageCell()
        cell.show(p,number:row+1,thumbnail:thumbs.object(forKey:p.path as NSString),unusual:deviationRows.indices.contains(row) ? deviationRows[row].reason:nil,review:ReviewProgress.state(p.id,active:reviewActive,pending:reviewPending))
        if cell.thumb.image==nil && !thumbnailPending.contains(p.path) {
            thumbnailPending.insert(p.path);let token=generation
            thumbnailQueue.addOperation{[weak self] in
                let image=try? Imaging.load(URL(fileURLWithPath:p.path),maxPixel:120)
                DispatchQueue.main.async {guard let self,self.generation==token else{return};self.thumbnailPending.remove(p.path)
                    if let image {self.thumbs.setObject(NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)),forKey:p.path as NSString,cost:image.width*image.height*4);self.table.reloadData(forRowIndexes:IndexSet(integer:row),columnIndexes:IndexSet(integer:0))}
                }
            }
        }
        return cell
    }
    /// A full reload resets the table's selection; that must not change the photograph on screen.
    func reloadPages(){reloading=true;table.reloadData();reloading=false}
    func tableViewSelectionDidChange(_ notification:Notification){
        guard !reloading else{return}
        // Extending the selection keeps the photograph on screen.
        let row=table.selectedRow
        guard project.pages.indices.contains(row),!table.selectedRowIndexes.contains(project.selected) || table.selectedRowIndexes.count==1 else{return}
        if row != project.selected || original==nil {project.selected=row;loadCurrent()}
    }
    func selectCurrent(){
        guard let i=current else {displayToken=UUID();original=nil;canvas.placeholder=CropCanvas.emptyProjectMessage;canvas.image=nil;refreshDetail();return}
        table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);table.scrollRowToVisible(i);loadCurrent()
    }
    func loadCurrent(){
        guard let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        original=nil;canvas.placeholder="";canvas.image=nil;canvas.preview=false;previewItem?.setSelected(false,at:0);canvas.quad=p.quad;canvas.fit();refreshDetail()
        displayQueue.cancelAllOperations()
        displayQueue.addOperation{[weak self] in
            let result=Result {try Imaging.load(URL(fileURLWithPath:p.path),maxPixel:3200)}
            DispatchQueue.main.async {guard let self,self.displayToken==token else{return};switch result {case .success(let image):self.original=image;self.canvas.image=image;if self.canvas.preview{self.renderPreview()};case .failure(let e):self.canvas.placeholder="Could not load this photograph";self.status.stringValue=e.localizedDescription}}
        }
    }
    func outputPixelSize(_ p:Page)->CGSize {
        if pixelSizes[p.path]==nil {pixelSizes[p.path]=Imaging.pixelSize(URL(fileURLWithPath:p.path))}
        guard let source=pixelSizes[p.path] else{return .zero}
        return OutputGeometry.pixelSize(quad:p.quad,sourceWidth:Double(source.width),sourceHeight:Double(source.height),rotation:p.rotation)
    }
    func refreshDetail(){
        let reviewed=project.pages.filter{$0.reviewed}.count
        inspectorControls.forEach{$0.isEnabled=current != nil}
        canvas.zones=current.flatMap{project.pages[$0].pictureZones} ?? []
        if !canvas.isDraggingSplit {canvas.split=current.flatMap{project.pages[$0].split}};canvas.rotation=current.map{project.pages[$0].rotation} ?? 0
        guard let i=current else{
            detail.stringValue="Import photographs to begin";note.isHidden=true;candidates.removeAllItems();counter.stringValue="";window?.subtitle="";resolutionLabel.stringValue="";return
        }
        let p=project.pages[i]
        let tilt=p.deskew.map{" · deskew "+$0.map{String(format:"%.1f°",$0)}.joined(separator:" / ")} ?? ""
        detail.stringValue="\(URL(fileURLWithPath:p.path).lastPathComponent)\n\(p.reviewed ? "Reviewed":p.status) · rotation \(p.rotation*90)°\(tilt)"
        let waiting=ReviewProgress.state(p.id,active:reviewActive,pending:reviewPending)
        note.stringValue=waiting?.label ?? p.reviewNote ?? "";note.isHidden=note.stringValue.isEmpty
        note.textColor=waiting == nil ? .labelColor:.secondaryLabelColor
        candidates.removeAllItems();candidates.addItem(withTitle:p.candidates.isEmpty ? "No proposals":"Choose proposal")
        for (j,c) in p.candidates.enumerated(){candidates.addItem(withTitle:"\(j+1) · \(c.source)")}
        if let selected=p.candidates.firstIndex(where:{$0.quad==p.quad}){candidates.selectItem(at:selected+1)}
        counter.stringValue="Photo \(i+1) of \(project.pages.count) · \(reviewed) reviewed";window?.subtitle=counter.stringValue
        let a=p.adjustments ?? Adjustments()
        cleanupControl.selectedSegment=Cleanup.allCases.firstIndex(of:a.cleanup) ?? 0;cleanupName.stringValue=a.cleanup.title
        brightnessSlider.doubleValue=a.brightness;contrastSlider.doubleValue=a.contrast
        despeckleControl.selectedSegment=min(3,max(0,a.despeckle ?? 0));despeckleControl.isEnabled=a.cleanup == .blackAndWhite
        let size=outputPixelSize(p),layout=OutputGeometry.layout(pixelWidth:Double(size.width),pixelHeight:Double(size.height),format:p.format)
        let fitted=p.format?.fitInto != nil
        shownSize=(Double(layout.imageRect.width)/72*2.54,Double(layout.imageRect.height)/72*2.54)
        if widthField.currentEditor()==nil {widthField.stringValue=String(format:"%.1f",shownSize.width)}
        if heightField.currentEditor()==nil {heightField.stringValue=String(format:"%.1f",shownSize.height)}
        widthField.isEnabled = !fitted;heightField.isEnabled = !fitted
        fitPopup.selectItem(at:p.format?.fitInto.flatMap{PaperSize.allCases.firstIndex(of:$0)}.map{$0+1} ?? 0)
        resolutionLabel.stringValue=size == .zero ? "":"Resolution is \(Int(layout.dpi.rounded())) DPI"+(fitted || p.format?.widthCM != nil ? "":" (assumed)")
    }
    func updateTitle(){
        let name=projectURL.deletingPathExtension().lastPathComponent,untitled=name.hasPrefix("Untitled ")
        window?.title=untitled ? "Untitled":name;window?.representedURL=untitled ? nil:projectURL
    }
    func save(){
        deviationCache=nil
        // An untitled project nothing was added to leaves no file behind.
        guard LaunchPolicy.shouldWrite(pageCount:project.pages.count,fileExists:FileManager.default.fileExists(atPath:projectURL.path)) else{updateTitle();return}
        do{
            try project.save(projectURL);updateTitle()
            if testDirectory == nil,notedRecent != projectURL {notedRecent=projectURL;NSDocumentController.shared.noteNewRecentDocumentURL(projectURL)}
        }catch{window?.subtitle="SAVE FAILED — \(error.localizedDescription)";status.stringValue="SAVE FAILED: \(error.localizedDescription)"}
    }

    // MARK: Editing and undo
    func edit(geometry:Bool=true,_ change:(inout Page)->Void){guard let i=current else{return};edit([i],geometry:geometry,change)}
    /// `geometry` is false for settings that an unfinished detection may safely ignore.
    func edit(_ indexes:[Int],geometry:Bool=true,_ change:(inout Page)->Void){
        guard !indexes.isEmpty else{return}
        undoStack.append(.pages(indexes.map{project.pages[$0]}));redoStack.removeAll()
        for i in indexes {change(&project.pages[i]);if geometry{project.pages[i].revision+=1}}
        finishEdit(indexes)
    }
    func finishEdit(_ indexes:[Int]){
        if let i=current {canvas.quad=project.pages[i].quad}
        save();refreshDetail();table.reloadData(forRowIndexes:IndexSet(indexes),columnIndexes:IndexSet(integer:0));if canvas.preview{renderPreview()}
        deviations?.refresh()
    }
    func invalidateWork(){queue.cancelAllOperations();splitQueue.cancelAllOperations();generation=UUID();thumbnailPending=[];detecting=false;endProgress(.detect);endProgress(.split)}
    func restructure(_ change:()->Void){
        undoStack.append(.structure(project.pages,project.selected));redoStack.removeAll();invalidateWork();change()
        project.selected=min(max(0,project.selected),max(0,project.pages.count-1));save();reloadPages();selectCurrent()
    }
    /// Applies an entry and returns its inverse.
    func exchange(_ entry:UndoEntry)->UndoEntry? {
        switch entry {
        case .pages(let old):
            var replaced:[Page]=[];let shown=current.map{project.pages[$0].id};var last:Int?
            for page in old {
                guard let i=project.pages.firstIndex(where:{$0.id==page.id}) else{continue}
                replaced.append(project.pages[i]);var restored=page;restored.revision=project.pages[i].revision+1;project.pages[i]=restored;last=i
            }
            if !old.contains(where:{$0.id==shown}),let last {project.selected=last}
            return replaced.isEmpty ? nil:.pages(replaced)
        case .structure(let pages,let selected):
            let inverse=UndoEntry.structure(project.pages,project.selected)
            invalidateWork();project.pages=Project.restoringStructure(pages,current:project.pages);project.selected=selected;return inverse
        }
    }
    // While a field is being edited, Undo and Redo belong to its text.
    @objc func undo(){if let text=editedText{text.undoManager?.undo();return};if adjusting{commitAdjustments()};guard let entry=undoStack.popLast() else{return};if let inverse=exchange(entry){redoStack.append(inverse)};save();reloadPages();selectCurrent()}
    @objc func redo(){if let text=editedText{text.undoManager?.redo();return};if adjusting{commitAdjustments()};guard let entry=redoStack.popLast() else{return};if let inverse=exchange(entry){undoStack.append(inverse)};save();reloadPages();selectCurrent()}

    // MARK: Navigation and crop actions
    func navigate(_ d:Int){guard let i=current else{return};project.selected=min(project.pages.count-1,max(0,i+d));selectCurrent();save()}
    func show(_ index:Int){guard project.pages.indices.contains(index) else{return};project.selected=index;selectCurrent();save()}
    @objc func previous(){navigate(-1)}
    @objc func next(){navigate(1)}
    @objc func firstPage(){show(0)}
    @objc func lastPage(){show(project.pages.count-1)}
    @objc func accept(){edit{$0.reviewed=true};navigate(1)}
    func nextMatching(_ test:(Page)->Bool){guard let i=current else{return};for d in 1...project.pages.count {let j=(i+d)%project.pages.count;if test(project.pages[j]){show(j);return}};NSSound.beep()}
    @objc func nextReview(){nextMatching{!$0.reviewed}}
    @objc func nextFlagged(){nextMatching{$0.flagged==true}}
    @objc func selectAllPages(){table.selectAll(nil);status.stringValue="\(table.selectedRowIndexes.count) pages selected — settings, flags, export and Send to Claude apply to all of them"}
    @objc func toggleFlag(){guard let i=current else{return};let on=project.pages[i].flagged != true;edit(targetIndexes,geometry:false){$0.flagged=on ? true:nil}}
    @objc func fit(){canvas.fit()}
    @objc func zoomIn(){canvas.zoom=min(8,canvas.zoom*1.25)}
    @objc func zoomOut(){canvas.zoom=max(0.5,canvas.zoom/1.25)}
    @objc func zoomSegment(_ sender:NSToolbarItemGroup){[zoomOut,fit,zoomIn][sender.selectedIndex]()}
    func turn(_ quarter:Int){
        guard let i=current else{return}
        // A split is measured across the output, so a quarter turn leaves nothing to keep: propose it afresh.
        let had=project.pages[i].split != nil
        edit{$0.rotation=($0.rotation+quarter+4)%4;$0.split=$0.split?.rotated(quarterTurns:quarter)}
        if had,project.pages[i].split==nil {proposeSplits([i],record:false)}
        if !canvas.preview{setPreview(true)}
    }

    // MARK: Page split
    @objc func proposeSplit(){proposeSplits(targetIndexes,record:true)}
    /// Looks for the fold on each page in the background. One undo step covers the whole request.
    func proposeSplits(_ indexes:[Int],record:Bool){
        guard !indexes.isEmpty else{return}
        let pages=indexes.map{project.pages[$0]},token=generation
        if record {undoStack.append(.pages(pages));redoStack.removeAll()}
        status.stringValue=pages.count==1 ? "Looking for the fold…":"Looking for the fold on \(pages.count) pages…"
        if pages.count>1 {beginProgress(.split,pages.count)}
        var found=0,finished=0
        for page in pages {
            splitQueue.addOperation{[weak self] in
                let result:Result<SplitProposal,Error>=autoreleasepool{Result{try SplitDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),quad:page.quad,rotation:page.rotation)}}
                DispatchQueue.main.async{guard let self,self.generation==token else{return}
                    finished+=1
                    // The crop or rotation may have changed while this ran; a proposal for the old shape is not applied.
                    if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),self.project.pages[i].quad==page.quad,self.project.pages[i].rotation==page.rotation,case .success(let proposal)=result {
                        self.project.pages[i].split=proposal.split;if proposal.confident{found+=1}
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.refreshDetail()}
                    }
                    self.stepProgress(.split,finished)
                    if finished==pages.count {
                        self.endProgress(.split)
                        self.status.stringValue=pages.count==1 ? (found==1 ? "Split proposed at the fold — drag it, or press , and . to move it":"No clear fold found; split placed at the centre — drag it, or press , and . to move it"):"Split proposed on \(pages.count) pages: \(found) at a fold, \(pages.count-found) at the centre"
                    }
                }
            }
        }
    }
    // MARK: Deskew, picture zones and deviations
    @objc func deskew(){
        let targets=targetIndexes;guard !targets.isEmpty else{return}
        let pages=targets.map{project.pages[$0]},token=generation
        undoStack.append(.pages(pages));redoStack.removeAll()
        status.stringValue=pages.count==1 ? "Measuring the tilt of the text…":"Measuring the tilt on \(pages.count) pages…"
        if pages.count>1 {beginProgress(.split,pages.count)}
        var found=0,finished=0
        for page in pages {
            splitQueue.addOperation{[weak self] in
                let result:Result<[Double]?,Error>=autoreleasepool{Result{try SkewDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),page:page)}}
                DispatchQueue.main.async{guard let self,self.generation==token else{return}
                    finished+=1
                    // Measured on the crop as it was; a crop, rotation or split changed since would not match.
                    if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),self.project.pages[i].quad==page.quad,self.project.pages[i].rotation==page.rotation,self.project.pages[i].split==page.split,case .success(let angles)=result {
                        self.project.pages[i].deskew=angles;if angles != nil{found+=1}
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.refreshDetail();if self.canvas.preview{self.renderPreview()}else if angles != nil{self.setPreview(true)}}
                    }
                    if pages.count>1 {self.stepProgress(.split,finished)}
                    if finished==pages.count {
                        if pages.count>1 {self.endProgress(.split)}
                        self.status.stringValue=pages.count==1 ? (found==1 ? "Deskewed — Option-, and Option-. turn it by 0.1°":"No clear tilt found; the page is left as it is"):"Deskewed \(found) of \(pages.count) pages; the rest showed no clear tilt"
                    }
                }
            }
        }
    }
    @objc func removeDeskew(){
        let targets=targetIndexes.filter{project.pages[$0].deskew != nil};guard !targets.isEmpty else{return}
        edit(targets,geometry:false){$0.deskew=nil};status.stringValue="Deskew removed"
    }
    func turnDeskew(_ delta:Double){
        guard let i=current else{return}
        let turned=Page.nudged(project.pages[i].deskew,by:delta,parts:Exporter.previewParts(project.pages[i]))
        edit(geometry:false){$0.deskew=turned};if !canvas.preview{setPreview(true)}
    }
    @objc func deskewCounterclockwise(){turnDeskew(-0.1)}
    @objc func deskewClockwise(){turnDeskew(0.1)}
    @objc func deskewSegment(_ sender:NSSegmentedControl){switch sender.selectedSegment {case 0:deskew();case 1:turnDeskew(-0.1);case 2:turnDeskew(0.1);default:removeDeskew()}}
    @objc func addZone(){
        guard current != nil,original != nil else{return}
        if canvas.preview{setPreview(false)}
        canvas.zoneMode=true;window.makeFirstResponder(canvas)
        status.stringValue="Drag across a picture to mark it · Escape cancels · right-click a zone to remove it"
    }
    func zoneDrawn(){
        guard let i=current else{return}
        status.stringValue=project.pages[i].adjustments?.cleanup == .blackAndWhite ? "Picture zone added; it keeps its gray tones":"Picture zone added; it takes effect when Cleanup is Black & White"
    }
    @objc func removeZones(){
        let targets=targetIndexes.filter{project.pages[$0].pictureZones != nil};guard !targets.isEmpty else{return}
        edit(targets,geometry:false){$0.pictureZones=nil};status.stringValue="Picture zones removed"
    }
    @objc func zoneSegment(_ sender:NSSegmentedControl){sender.selectedSegment==0 ? addZone():removeZones()}
    @objc func showDeviations(){
        if deviations == nil {deviations=DeviationsController(owner:self)}
        deviations!.show()
    }
    @objc func nextOutlier(){
        guard let i=current,let next=Deviation.nextOutlier(after:i,in:deviationRows) else{NSSound.beep();status.stringValue="No unusual pages";return}
        show(next);status.stringValue="Unusual \(deviationRows[next].reason ?? "crop") compared with the rest of the project"
    }
    @objc func removeSplit(){
        let targets=targetIndexes.filter{project.pages[$0].split != nil};guard !targets.isEmpty else{return}
        edit(targets,geometry:false){$0.split=nil};status.stringValue=targets.count==1 ? "Split removed; this photograph exports as one page":"Split removed from \(targets.count) pages"
    }
    func moveSplit(_ delta:Double){
        guard let i=current,let split=project.pages[i].split else{NSSound.beep();return}
        let moved=split.moved(by:delta);if moved != split {edit(geometry:false){$0.split=moved}}
    }
    @objc func moveSplitLeft(){moveSplit(-0.002)}
    @objc func moveSplitRight(){moveSplit(0.002)}
    @objc func splitSegment(_ sender:NSSegmentedControl){switch sender.selectedSegment {case 0:proposeSplit();case 1:moveSplitLeft();case 2:moveSplitRight();default:removeSplit()}}
    @objc func rotate(){turn(1)}
    @objc func rotateLeft(){turn(-1)}
    @objc func resetCrop(){edit{$0.setManualCrop(.full)}}
    @objc func copyPrevious(){
        guard let i=current,i>0 else{return}
        let q=project.pages[i-1].quad
        edit{$0.setManualCrop(q)}
    }
    @objc func shrinkCrop(){resizeCrop(1/1.02)}
    @objc func expandCrop(){resizeCrop(1.02)}
    @objc func sizeSegment(_ sender:NSSegmentedControl){sender.selectedSegment==0 ? shrinkCrop():expandCrop()}
    @objc func cropSegment(_ sender:NSSegmentedControl){[detectCurrent,resetCrop,copyPrevious][sender.selectedSegment]()}
    func resizeCrop(_ factor:Double){
        guard let i=current,let q=project.pages[i].quad.scaled(by:factor) else{return}
        if q != project.pages[i].quad {edit{$0.setManualCrop(q)}}
    }
    func resizeSide(_ key:String,inward:Bool){
        guard let i=current else{return}
        let edge=["h":3,"j":2,"k":0,"l":1][key]!
        let step=0.005*(inward ? -1.0:1.0)
        let delta=Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0)
        guard let q=project.pages[i].quad.movingEdge(edge,by:delta),q != project.pages[i].quad else{return}
        edit{$0.setManualCrop(q)}
    }
    @objc func reversePages(){guard project.pages.count>1 else{return};restructure{project.pages.reverse();project.selected=project.pages.count-1-project.selected}}
    @objc func removePages(){
        let targets=targetIndexes;guard let first=targets.min() else{return}
        restructure{for i in targets.sorted(by:>){project.pages.remove(at:i)};project.selected=first}
        status.stringValue="Removed \(targets.count) from the project; the photographs themselves are untouched"
    }
    func setPreview(_ on:Bool){
        canvas.preview=on;previewItem?.setSelected(on,at:0)
        if on{renderPreview()}else if original != nil{displayToken=UUID();canvas.image=original;canvas.fit()}
    }
    @objc func togglePreview(){setPreview(!canvas.preview)}
    func renderPreview(){guard let image=original,let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        displayQueue.cancelAllOperations()
        displayQueue.addOperation{[weak self] in let result=Result{try Exporter.preview(image,page:p)};DispatchQueue.main.async {guard let self,self.displayToken==token,self.canvas.preview else{return};switch result{
            case .success(let output):
                // Keep zoom and pan while only the tones change.
                let resized=self.canvas.image?.width != output.width || self.canvas.image?.height != output.height
                self.canvas.image=output;if resized{self.canvas.fit()}
            case .failure(let e):self.showError(e)}}}
    }
    @objc func candidateChanged(){guard let i=current else{return};let j=candidates.indexOfSelectedItem-1;guard project.pages[i].candidates.indices.contains(j) else{return};let q=project.pages[i].candidates[j].quad;edit{$0.selectProposal(q)}}
    func cycleCandidate(_ delta:Int){guard candidates.numberOfItems>1 else{return};let count=candidates.numberOfItems-1;let current=candidates.indexOfSelectedItem-1;let index=(current<0 ? (delta>0 ? 0:count-1):(current+delta+count)%count)+1;candidates.selectItem(at:index);candidateChanged();candidates.selectItem(at:index)}
    @objc func previousCandidate(){cycleCandidate(-1)}
    @objc func nextCandidate(){cycleCandidate(1)}

    // MARK: Image adjustments and page format
    @objc func adjustmentChanged(_ sender:Any?){
        var a=Adjustments();a.cleanup=Cleanup.allCases[max(0,cleanupControl.selectedSegment)];a.brightness=brightnessSlider.doubleValue;a.contrast=contrastSlider.doubleValue
        // Specks only exist once the page is black and white.
        a.despeckle=a.cleanup == .blackAndWhite && despeckleControl.selectedSegment>0 ? despeckleControl.selectedSegment:nil;despeckleControl.isEnabled=a.cleanup == .blackAndWhite
        setAdjustments(a)
    }
    @objc func resetAdjustments(){guard current != nil else{return};cleanupControl.selectedSegment=0;brightnessSlider.doubleValue=0;contrastSlider.doubleValue=0;despeckleControl.selectedSegment=0;despeckleControl.isEnabled=false;setAdjustments(Adjustments())}
    /// A slider drag is one undo step: the snapshot is taken at its first change and saved once it settles.
    func setAdjustments(_ a:Adjustments){
        let targets=targetIndexes;guard !targets.isEmpty else{return}
        if !adjusting {undoStack.append(.pages(targets.map{project.pages[$0]}));redoStack.removeAll();adjusting=true}
        for i in targets {project.pages[i].adjustments=a.isIdentity ? nil:a}
        cleanupName.stringValue=a.cleanup.title
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(commitAdjustments),object:nil)
        perform(#selector(commitAdjustments),with:nil,afterDelay:0.2)
        if canvas.preview{renderPreview()}else{setPreview(true)}
    }
    @objc func commitAdjustments(){
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(commitAdjustments),object:nil)
        guard adjusting else{return};adjusting=false;save();table.reloadData(forRowIndexes:IndexSet(targetIndexes),columnIndexes:IndexSet(integer:0))
    }
    @objc func formatChanged(_ sender:NSControl){
        guard let i=current else{return}
        var f=project.pages[i].format ?? PageFormat()
        let size=outputPixelSize(project.pages[i])
        if sender===fitPopup {f.fitInto=fitPopup.indexOfSelectedItem>0 ? PaperSize.allCases[fitPopup.indexOfSelectedItem-1]:nil}
        else if sender===widthField {
            let v=widthField.doubleValue;guard abs(v-shownSize.width)>=0.05 else{return finishField()}
            f.widthCM=v>0 ? v:nil
        } else if sender===heightField {
            let v=heightField.doubleValue;guard abs(v-shownSize.height)>=0.05 else{return finishField()}
            f.widthCM=v>0 && size.height>0 ? v*Double(size.width/size.height):nil
        }
        let value=f==PageFormat() ? nil:f
        edit(targetIndexes,geometry:false){$0.format=value}
        finishField()
    }
    /// Return hands the keyboard back to the canvas so single-key commands work again.
    func finishField(){if let e=NSApp.currentEvent,e.type == .keyDown,[36,76].contains(e.keyCode){window.makeFirstResponder(canvas)}}
    @objc func copySettings(){guard let i=current else{return};copiedSettings=(project.pages[i].adjustments,project.pages[i].format);status.stringValue="Copied image adjustments and page format"}
    @objc func pasteSettings(){guard let s=copiedSettings else{return};let targets=targetIndexes;edit(targets,geometry:false){$0.adjustments=s.0;$0.format=s.1};status.stringValue="Pasted settings to \(targets.count) page\(targets.count==1 ? "":"s")"}
    @objc func applySettingsToAll(){
        guard let i=current else{return};let a=project.pages[i].adjustments,f=project.pages[i].format
        edit(Array(project.pages.indices),geometry:false){$0.adjustments=a;$0.format=f};status.stringValue="Applied this page's adjustments and format to all \(project.pages.count) pages"
    }

    // MARK: Projects
    @objc func newProject(){
        save()
        let panel=NSSavePanel();panel.nameFieldStringValue="Book.kettlestitch";panel.message="Choose where the new collection will autosave."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{let fresh=Project();try fresh.save(url);stop();project=fresh;projectURL=url;undoStack=[];redoStack=[];save();reloadPages();selectCurrent()}catch{showError(error)}
    }
    @objc func importImages(){
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true;panel.message="Choose photographs or a folder. Subfolders are not imported."
        guard panel.runModal() == .OK else{return}
        receive(panel.urls)
    }
    func application(_ application:NSApplication,open urls:[URL]){if window==nil {pendingOpen += urls} else {receive(urls)}}
    /// Files and folders from the Import panel, a drop on the window or a drop on the app's icon.
    /// A project file is opened; photographs are added to the project that is open.
    func receive(_ urls:[URL]){
        let incoming=ImportPolicy.sort(urls,existing:Set(project.pages.map{$0.path})){url in
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:url.path,isDirectory:&directory),directory.boolValue else{return nil}
            return (try? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? []
        }
        if let file=incoming.project {save();open(file);return}
        guard !incoming.photographs.isEmpty else{status.stringValue="Nothing new to import";return}
        let added=incoming.photographs.map{Page(path:$0.path)},wasEmpty=project.pages.isEmpty
        restructure{project.pages += added;if wasEmpty{project.selected=0}}
        status.stringValue="Imported \(added.count) photograph\(added.count==1 ? "":"s") · B detects pending pages"
    }
    @objc func openProject(){let panel=NSOpenPanel();panel.allowedContentTypes=ImportPolicy.projectExtensions.compactMap{UTType(filenameExtension:$0)}+[.json];guard panel.runModal() == .OK,let url=panel.url else{return};open(url)}
    @objc func openRecent(_ sender:NSMenuItem){if let url=sender.representedObject as? URL{save();open(url)}}
    func open(_ url:URL){
        do{let loaded=try Project.read(url);stop();generation=UUID();project=loaded;project.selected=min(max(0,project.selected),max(0,project.pages.count-1));projectURL=url;save();undoStack=[];redoStack=[];thumbs.removeAllObjects();thumbnailPending=[];pixelSizes=[:];reloadPages();selectCurrent();status.stringValue="Opened \(url.lastPathComponent)"}catch{showError(error)}
    }
    @objc func saveAs(){let panel=NSSavePanel();panel.nameFieldStringValue="Book.kettlestitch";guard panel.runModal() == .OK,let url=panel.url else{return};do{try project.save(url);projectURL=url;save();status.stringValue="Saved \(url.lastPathComponent)"}catch{showError(error)}}

    // MARK: Background work
    func beginProgress(_ kind:ProgressTracker.Kind,_ total:Int){tracker.begin(kind,total:total);showProgress()}
    func stepProgress(_ kind:ProgressTracker.Kind,_ done:Int){tracker.advance(kind,to:done);showProgress()}
    func endProgress(_ kind:ProgressTracker.Kind){tracker.end(kind);showProgress()}
    /// Detection, export, Claude review and split proposals can overlap; the bar shows them together and hides when all are done.
    func showProgress(){
        progress.isHidden = !tracker.isActive;stopButton.isHidden = !tracker.isActive
        if tracker.isIndeterminate {progress.isIndeterminate=true;progress.startAnimation(nil)}
        else {progress.stopAnimation(nil);progress.isIndeterminate=false;progress.maxValue=1;progress.doubleValue=tracker.fraction}
    }
    @objc func detectCurrent(){guard let i=current else{return};runDetection([i])}
    @objc func detectPending(){runDetection(project.pages.indices.filter{project.pages[$0].status=="Pending"})}
    func runDetection(_ indexes:[Int]){
        guard !detecting,!indexes.isEmpty else{return};detecting=true;let token=generation
        let snapshots=indexes.map{($0,project.pages[$0])}
        beginProgress(.detect,snapshots.count)
        for (number,item) in snapshots.enumerated(){let (index,page)=item
            queue.addOperation{[weak self] in
                let result:Result<[Candidate],Error>=autoreleasepool{Result {try Detector().detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600))}}
                DispatchQueue.main.async {guard let self,self.generation==token else{return}
                    if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),self.project.pages[i].revision==page.revision {
                        switch result {
                        case .success(let found):
                            self.project.pages[i].candidates=Candidate.merging(detected:found,into:self.project.pages[i].candidates)
                            if self.project.pages[i].status=="Pending" {
                                if let best=found.first {self.project.pages[i].quad=best.quad;self.project.pages[i].status="Check proposal"}else{self.project.pages[i].status="No boundary — crop manually"}
                            }
                        case .failure(let error):self.project.pages[i].status="Detection error";self.status.stringValue=error.localizedDescription
                        }
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:index),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.canvas.quad=self.project.pages[i].quad;self.refreshDetail()}
                    }
                    self.status.stringValue="Detection \(number+1)/\(snapshots.count) · review every proposal";self.stepProgress(.detect,number+1)
                    if number==snapshots.count-1 {self.detecting=false;self.endProgress(.detect)}
                }
            }
        }
    }
    @objc func stop(){invalidateWork();exportCancelled=true;reviewCancelled=true;reviewProcess?.terminate();status.stringValue="Stopped; completed edits are saved"}
    @objc func exportImages(){
        guard !exporting,!project.pages.isEmpty else{return}
        let selected=targetIndexes
        let sheet=ExportSheetController(options:exportOptions,selectedCount:selected.count,totalCount:project.pages.count);exportSheet=sheet
        sheet.begin(on:window){[weak self] options,selectedOnly in
            guard let self else{return};self.exportSheet=nil
            guard let options else{return}
            self.exportOptions=options;if let data=try? JSONEncoder().encode(options){UserDefaults.standard.set(data,forKey:"exportOptions")}
            let pages=selectedOnly ? selected.filter{self.project.pages.indices.contains($0)}.map{self.project.pages[$0]}:self.project.pages
            DispatchQueue.main.async{self.chooseDestination(pages,options)}
        }
    }
    func chooseDestination(_ pages:[Page],_ options:ExportOptions){
        if options.format == .pdf {
            let panel=NSSavePanel();panel.allowedContentTypes=[.pdf];panel.nameFieldStringValue=projectURL.deletingPathExtension().lastPathComponent+".pdf"
            panel.beginSheetModal(for:window){[weak self] response in if response == .OK,let url=panel.url{self?.runExport(pages,options,url)}}
        } else {
            let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true;panel.prompt="Export"
            panel.message="Choose a destination. A new dated subfolder will hold the corrected \(options.format.title) files."
            panel.beginSheetModal(for:window){[weak self] response in
                guard let self,response == .OK,let parent=panel.url else{return}
                let folder=parent.appendingPathComponent("KettleStitch-"+ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")+"-"+UUID().uuidString.prefix(6))
                do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);self.runExport(pages,options,folder)}catch{self.showError(error)}
            }
        }
    }
    /// `destination` is the PDF file, or the folder that receives one image per page.
    func runExport(_ pages:[Page],_ options:ExportOptions,_ destination:URL){
        guard !exporting,!pages.isEmpty else{return}
        exportCancelled=false;exporting=true;beginProgress(.export,pages.count);status.stringValue="Exporting \(pages.count) pages…"
        exportQueue.addOperation{[weak self] in
            var completed=0
            func cancelled()->Bool {DispatchQueue.main.sync{self?.exportCancelled ?? true}}
            func report(){completed+=1;let done=completed;DispatchQueue.main.async{self?.status.stringValue="Exported \(done)/\(pages.count)";self?.stepProgress(.export,done)}}
            do{
                var finished=true
                if options.format == .pdf {
                    let temp=destination.deletingLastPathComponent().appendingPathComponent(".partial-\(UUID().uuidString).pdf")
                    do{
                        let writer=try PDFWriter(url:temp,password:options.password)
                        for page in pages {if cancelled(){finished=false;break};try autoreleasepool{try writer.add(page,options:options)};report()}
                        writer.close()
                        if finished {
                            if FileManager.default.fileExists(atPath:destination.path){try FileManager.default.removeItem(at:destination)}
                            try FileManager.default.moveItem(at:temp,to:destination)
                        } else {try? FileManager.default.removeItem(at:temp)}
                    }catch{try? FileManager.default.removeItem(at:temp);throw error}
                } else {
                    for (i,page) in pages.enumerated(){if cancelled(){finished=false;break}
                        try autoreleasepool{
                            let name=String(format:"%04d-",i+1)+URL(fileURLWithPath:page.path).deletingPathExtension().lastPathComponent
                            try Exporter.writeImages(page,in:destination,name:name,options:options)
                        };report()
                    }
                }
                let done=completed,complete=finished
                DispatchQueue.main.async{guard let self else{return};self.exporting=false;self.endProgress(.export)
                    self.status.stringValue=complete ? "Exported \(done) pages to \(destination.lastPathComponent)":options.format == .pdf ? "Export stopped; no PDF was written":"Export stopped after \(done)/\(pages.count)"
                    if complete,self.testDirectory == nil {NSWorkspace.shared.activateFileViewerSelecting([destination])}
                }
            }catch{DispatchQueue.main.async{self?.exporting=false;self?.endProgress(.export);self?.showError(error)}}
        }
    }

    // MARK: Claude
    var claudeModel: String {
        let saved=UserDefaults.standard.string(forKey:"claudeModel")
        return ClaudeReview.models.contains{$0.id==saved} ? saved!:ClaudeReview.models[0].id
    }
    @objc func showSettings(){
        if settings == nil {settings=SettingsController()}
        settings!.show()
    }
    /// Asks Claude to judge the crop of every targeted page. Fixes arrive as proposals; the crop itself is never replaced.
    @objc func sendToClaude(){
        let targets=targetIndexes;guard !reviewing,!targets.isEmpty else{return}
        guard let key=Keychain.read(),!key.isEmpty else{showSettings();settings?.explain("Add an Anthropic API key to send crops to Claude.");return}
        guard let executable=ClaudeReview.locateExecutable() else{showError(CropError.message("The claude command-line tool was not found. Install Claude Code, then try again."));return}
        let pages=targets.map{project.pages[$0]},model=claudeModel,token=generation
        beginReview(pages,model:ClaudeReview.models.first{$0.id==model}?.title ?? model)
        reviewQueue.addOperation{[weak self] in
            var good=0,fixes=0,failure:Error?
            for (number,page) in pages.enumerated() {
                let proceed=DispatchQueue.main.sync{()->Bool in
                    guard let self,!self.reviewCancelled,self.generation==token else{return false}
                    self.reviewWaiting(for:page,number:number+1);return true
                }
                if !proceed{break}
                let result=Result{try ClaudeReview.run(page,model:model,apiKey:key,executable:executable){process in DispatchQueue.main.async{self?.reviewProcess=process}}}
                var stop=false
                DispatchQueue.main.sync{
                    guard let self,self.generation==token,!self.reviewCancelled else{stop=true;return}
                    self.stepProgress(.review,number+1)
                    switch result {
                    case .failure(let error):failure=error;stop=true
                    case .success(let review):
                        if review.quad != nil{fixes+=1}else if review.good{good+=1}
                        self.reviewPending.remove(page.id);self.reviewActive=nil
                        self.record(review,for:page,done:number+1,of:pages.count)
                    }
                }
                if stop{break}
            }
            DispatchQueue.main.async{guard let self else{return}
                let stopped=self.reviewCancelled;self.endReview()
                if let failure,!stopped {self.status.stringValue="Claude review failed";self.showError(failure)}
                else if stopped {self.status.stringValue="Stopped; Claude's finished reviews are kept"}
                else if pages.count>1 {self.status.stringValue="Claude reviewed \(good+fixes) of \(pages.count): \(good) good, \(fixes) with a proposed fix — look for “Claude” under Proposals"}
            }
        }
    }
    /// Rows of pages still with Claude, so their waiting state can be redrawn.
    func reloadReviewRows(_ ids:Set<UUID>){
        let rows=IndexSet(project.pages.indices.filter{ids.contains(project.pages[$0].id)})
        table.reloadData(forRowIndexes:rows,columnIndexes:IndexSet(integer:0));refreshDetail()
    }
    func beginReview(_ pages:[Page],model:String){
        reviewing=true;reviewCancelled=false;reviewModel=model;reviewTotal=pages.count;reviewNumber=0;reviewStarted=Date()
        reviewPending=Set(pages.map{$0.id});reviewActive=nil
        beginProgress(.review,pages.count)
        let timer=Timer(timeInterval:1,repeats:true){[weak self] _ in self?.updateReviewStatus()}
        RunLoop.main.add(timer,forMode:.common);reviewTimer=timer
        reloadReviewRows(reviewPending);updateReviewStatus()
    }
    func reviewWaiting(for page:Page,number:Int){
        reviewActive=page.id;reviewNumber=number;reviewStarted=Date()
        reloadReviewRows([page.id]);updateReviewStatus()
    }
    func updateReviewStatus(){
        guard reviewing else{return}
        let name=project.pages.first{$0.id==reviewActive}.map{URL(fileURLWithPath:$0.path).lastPathComponent}
        let seconds=Int(Date().timeIntervalSince(reviewStarted))
        status.stringValue=ReviewProgress.status(model:reviewModel,number:reviewNumber,total:reviewTotal,name:name,seconds:seconds)
    }
    func endReview(){
        let waiting=reviewPending
        reviewTimer?.invalidate();reviewTimer=nil;reviewing=false;reviewProcess=nil;reviewPending=[];reviewActive=nil
        endProgress(.review)
        reloadReviewRows(waiting)
    }
    func record(_ review:CropReview,for page:Page,done:Int,of total:Int){
        guard let i=project.pages.firstIndex(where:{$0.id==page.id}) else{return}
        // Claude saw the crop as it was when sent; a verdict on a crop edited since would mislead.
        guard project.pages[i].record(review,sentQuad:page.quad) else{
            if total==1 {status.stringValue="The crop changed while Claude was looking, so its answer was not kept"}
            return
        }
        save();table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
        if current==i {refreshDetail()}
        if total==1 {status.stringValue=(review.quad != nil ? "Claude proposes a fix · press ] or choose “Claude” under Proposal to try it":review.good ? "Claude: crop looks right":"Claude: no usable fix")}
    }

    func showError(_ error:Error){let alert=NSAlert(error:error);alert.runModal()}
    @objc func cornerSegment(_ sender:NSSegmentedControl){selectCorner([0,1,3,2][sender.selectedSegment])}
    func selectCorner(_ i:Int,keyboard:Bool=false){if canvas.preview{setPreview(false)};canvas.selectCorner(i,keyboard:keyboard);window.makeFirstResponder(canvas)}
    func handleKey(_ e:NSEvent)->Bool {
        guard !e.modifierFlags.contains(.command),!e.modifierFlags.contains(.control),let key=e.charactersIgnoringModifiers?.lowercased() else{return false}
        if [123,124,125,126].contains(e.keyCode),canvas.keyboardSelection {let mapping:[UInt16:String]=[123:"a",124:"d",125:"s",126:"w"];canvas.nudge(mapping[e.keyCode]!,large:e.modifierFlags.contains(.shift));return true}
        if ["h","j","k","l"].contains(key) {
            if e.modifierFlags.contains(.option) {
                guard let i=current else{return true}
                let step=e.modifierFlags.contains(.shift) ? 0.02:0.005
                let delta=Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0)
                if let q=project.pages[i].quad.translated(by:delta),q != project.pages[i].quad {
                    edit{$0.setManualCrop(q)}
                }
            } else {resizeSide(key,inward:e.modifierFlags.contains(.shift))}
            return true
        }
        switch key {
        case "g":newProject();case "i":importImages();case "o":openProject();case "s":saveAs();case "d":detectCurrent();case "b":detectPending();case "e":exportImages()
        case "p":togglePreview()
        case "r":e.modifierFlags.contains(.shift) ? rotateLeft():rotate()
        case "a":sendToClaude();case "m":toggleFlag()
        case "v":e.modifierFlags.contains(.shift) ? removeSplit():proposeSplit()
        case ",","<":e.modifierFlags.contains(.option) ? turnDeskew(-0.1):moveSplit(e.modifierFlags.contains(.shift) ? -0.01:-0.002)
        case ".",">":e.modifierFlags.contains(.option) ? turnDeskew(0.1):moveSplit(e.modifierFlags.contains(.shift) ? 0.01:0.002)
        case "t":e.modifierFlags.contains(.shift) ? removeDeskew():deskew()
        case "w":e.modifierFlags.contains(.shift) ? removeZones():addZone()
        case "u":nextOutlier()
        case "f","0":fit();case "+","=":zoomIn();case "-":zoomOut();case "c":copyPrevious();case ";":shrinkCrop();case "'":expandCrop();case "x":resetCrop();case "z":undo();case "y":redo();case "n":nextReview();case "[":cycleCandidate(-1);case "]":cycleCandidate(1)
        case "1","2","3","4":selectCorner([0,1,3,2][Int(key)!-1],keyboard:true)
        case "5","6","7","8":if canvas.preview{setPreview(false)};canvas.selectEdge([0,3,1,2][Int(key)!-5],keyboard:true);window.makeFirstResponder(canvas)
        case "?","/":help()
        default:
            if e.keyCode==53 {if canvas.zoneMode{canvas.zoneMode=false;status.stringValue="Picture zone cancelled"}else if canvas.hasSelection{canvas.releaseCorner()}else{stop()}}
            else if e.keyCode==123 {navigate(-1)}else if e.keyCode==124{navigate(1)}else if e.keyCode==36{accept()}
            else if e.keyCode==115 {firstPage()}else if e.keyCode==119{lastPage()}
            else if e.keyCode==116{navigate(-10)}else if e.keyCode==121{navigate(10)}else{return false}
        }
        return true
    }
    @objc func help(){if shortcuts == nil {shortcuts=ShortcutsController()};shortcuts!.show()}
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=AppDelegate()
app.delegate=delegate
app.run()

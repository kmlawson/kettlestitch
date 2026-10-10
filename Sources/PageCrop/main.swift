import AppKit
import CropCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var window: NSWindow!
    let canvas=CropCanvas()
    let table=NSTableView()
    let status=NSTextField(labelWithString:"Open photographs to begin")
    let detail=NSTextField(wrappingLabelWithString:"")
    let candidates=NSPopUpButton()
    let previewButton=NSButton(checkboxWithTitle:"Corrected preview  [P]",target:nil,action:nil)
    let queue=OperationQueue()
    let displayQueue=OperationQueue()
    let exportQueue=OperationQueue()
    let thumbnailQueue=OperationQueue()
    var project=Project()
    var projectURL: URL!
    var generation=UUID()
    var displayToken=UUID()
    var original: CGImage?
    var undoStack: [(UUID,Page)]=[]
    var redoStack: [(UUID,Page)]=[]
    var detecting=false
    var exportCancelled=false
    var exporting=false
    var shortcutMonitor: Any?
    var thumbs=NSCache<NSString,NSImage>()
    var thumbnailPending=Set<String>()
    var current: Int? {project.pages.indices.contains(project.selected) ? project.selected:nil}
    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.maxConcurrentOperationCount=1;queue.qualityOfService = .utility
        displayQueue.maxConcurrentOperationCount=1;displayQueue.qualityOfService = .userInitiated
        exportQueue.maxConcurrentOperationCount=1
        thumbnailQueue.maxConcurrentOperationCount=1;thumbnailQueue.qualityOfService = .utility
        thumbs.totalCostLimit=24*1024*1024
        let support=ProcessInfo.processInfo.environment["PAGECROP_TEST_DIR"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PageCrop")
        do {try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)} catch {showError(error)}
        projectURL=support.appendingPathComponent("Recovery.pagecrop")
        if ProcessInfo.processInfo.environment["PAGECROP_TEST_DIR"] == nil,let last=UserDefaults.standard.string(forKey:"lastProject"),FileManager.default.fileExists(atPath:last) {projectURL=URL(fileURLWithPath:last)}
        if let index=CommandLine.arguments.firstIndex(of:"--project"),CommandLine.arguments.count>index+1 {projectURL=URL(fileURLWithPath:CommandLine.arguments[index+1])}
        if FileManager.default.fileExists(atPath:projectURL.path) {
            do {project=try Project.read(projectURL);project.selected=min(max(0,project.selected),max(0,project.pages.count-1))} catch {showError(error);projectURL=support.appendingPathComponent("Recovery-"+UUID().uuidString+".pagecrop")}
        }
        buildUI();buildMenus();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        canvas.onCommit={[weak self] q in self?.edit{$0.quad=q;$0.status="Manual";$0.reviewed=false}}
        canvas.onNavigate={[weak self] delta in self?.navigate(delta)}
        canvas.onAccept={[weak self] in self?.accept()}
        canvas.onUndo={[weak self] in self?.undo()}
        shortcutMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self, NSApp.keyWindow===self.window, !(self.window.firstResponder is NSTextView), !(self.window.firstResponder is NSTextField) else {return event}
            return self.handleKey(event) ? nil:event
        }
        table.reloadData();selectCurrent()
        if CommandLine.arguments.contains("--smoke"),let dir=ProcessInfo.processInfo.environment["PAGECROP_TEST_DIR"] {
            DispatchQueue.main.asyncAfter(deadline:.now()+3){
                self.window.contentView!.layoutSubtreeIfNeeded()
                let view=self.window.contentView!,rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                view.cacheDisplay(in:view.bounds,to:rep)
                try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:dir).appendingPathComponent("ui.png"))
                let didLoad=self.original != nil
                let canvas=self.canvas
                func mouse(_ type:NSEvent.EventType,_ point:CGPoint)->NSEvent {
                    NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:self.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                }
                let originalQuad=canvas.quad
                let smokeImage=canvas.image
                let cornerPoint=canvas.position(originalQuad.points[0])
                canvas.mouseDown(with:mouse(.leftMouseDown,cornerPoint))
                precondition(canvas.isMagnifierVisible)
                canvas.mouseUp(with:mouse(.leftMouseUp,cornerPoint))
                precondition(!canvas.isMagnifierVisible && !canvas.keyboardSelection)
                let a=canvas.position(originalQuad.points[0]),b=canvas.position(originalQuad.points[1])
                let midpoint=CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
                canvas.mouseDown(with:mouse(.leftMouseDown,midpoint))
                precondition(canvas.selectedEdge==0 && !canvas.keyboardSelection)
                let dragged=CGPoint(x:midpoint.x,y:midpoint.y+8)
                canvas.mouseDragged(with:mouse(.leftMouseDragged,dragged))
                precondition(canvas.quad.points[0] != originalQuad.points[0] && canvas.quad.points[1] != originalQuad.points[1])
                precondition(canvas.quad.points[2]==originalQuad.points[2] && canvas.quad.points[3]==originalQuad.points[3])
                canvas.mouseUp(with:mouse(.leftMouseUp,dragged))
                precondition(!canvas.isMagnifierVisible)
                canvas.selectEdge(1);let edgeBefore=canvas.quad;canvas.nudge("a",large:false)
                precondition(canvas.quad.points[1] != edgeBefore.points[1] && canvas.quad.points[2] != edgeBefore.points[2])
                canvas.selectCorner(0);precondition(canvas.isMagnifierVisible);canvas.releaseCorner()
                canvas.quad=originalQuad;self.project.pages[0].quad=originalQuad
                func key(_ chars:String,_ code:UInt16,_ flags:NSEvent.ModifierFlags=[]){
                    let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:self.window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!
                    precondition(self.handleKey(event))
                }
                for (number,edge) in [("5",0),("6",3),("7",1),("8",2)] {
                    key(number,0);precondition(canvas.selectedEdge==edge && canvas.keyboardSelection)
                }
                key("1",0);precondition(canvas.keyboardSelection)
                let click=canvas.position(canvas.quad.points[0])
                canvas.mouseDown(with:mouse(.leftMouseDown,click));canvas.mouseUp(with:mouse(.leftMouseUp,click))
                precondition(!canvas.keyboardSelection)
                let selected=self.project.selected
                key("6",0);let q=canvas.quad
                key("\u{F703}",124)
                precondition(self.project.selected==selected && canvas.quad != q)
                key("\u{1b}",53);precondition(!canvas.hasSelection)
                key("\u{F703}",124);precondition(self.project.selected==selected+1)
                key("c",8);precondition(self.project.pages[1].quad==self.project.pages[0].quad)
                key("c",8);precondition(self.project.pages[1].quad==self.project.pages[0].quad)
                key("'",39);let expanded=self.project.pages[1].quad
                precondition(expanded.area>=self.project.pages[0].quad.area)
                key(";",41);precondition(self.project.pages[1].quad.area<expanded.area)
                let inset=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
                for (letter,edge) in [("h",3),("j",2),("k",0),("l",1)] {
                    self.project.pages[1].quad=inset;canvas.quad=inset
                    key(letter,0);let moved=self.project.pages[1].quad
                    precondition(moved.area>inset.area)
                    for index in 0..<4 {precondition((moved.points[index] != inset.points[index]) == (index==edge || index==(edge+1)%4))}
                    key(letter,0,.shift);precondition(self.project.pages[1].quad.distance(inset)<1e-10)
                }
                self.navigate(-1)
                canvas.image=smokeImage
                canvas.quad=originalQuad;self.project.pages[0].quad=originalQuad
                print("ARROW_SELECTION_ESCAPE_EDGE_MAPPING_COPY_SCALE passed")
                print("MOUSE_EDGE_LOUPE_KEYBOARD passed")
                let before=self.project.pages[0].quad
                self.selectCorner(0);self.canvas.nudge("d",large:false)
                precondition(self.project.pages[0].quad != before)
                self.undo();precondition(self.project.pages[0].quad == before)
                self.redo();precondition(self.project.pages[0].quad != before)
                self.accept();precondition(self.project.selected==1 && self.project.pages[0].reviewed)
                self.navigate(-1)
                do{try Imaging.export(self.project.pages[0],to:URL(fileURLWithPath:dir).appendingPathComponent("export-check.jpg"));print("EDIT_UNDO_REDO_REVIEW_EXPORT passed")}catch{print("SMOKE_ERROR \(error)")}
                print("UI_SMOKE pages=\(self.project.pages.count) loaded=\(didLoad) canvas=\(self.canvas.bounds)")
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification: Notification){queue.cancelAllOperations();save()}
    func button(_ title:String,_ action:Selector)->NSButton {let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    func buildUI() {
        window=NSWindow(contentRect:NSRect(x:100,y:100,width:1320,height:860),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="PageCrop — Book photograph cropper";window.minSize=NSSize(width:1200,height:740)
        let root=NSView();root.wantsLayer=true;root.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor;window.contentView=root
        let top=NSStackView(views:[button("New  G",#selector(newProject)),button("Import  I",#selector(importImages)),button("Open project  O",#selector(openProject)),button("Save as  S",#selector(saveAs)),button("Detect  D",#selector(detectCurrent)),button("Detect pending  B",#selector(detectPending)),button("Stop  Esc",#selector(stop)),button("Export  E",#selector(exportImages)),button("Keys  ?",#selector(help))]);top.spacing=8
        let bottom=NSStackView(views:[button("‹ Previous  ←",#selector(previous)),button("Next  →",#selector(next)),button("Accept + next  ↵",#selector(accept)),button("Needs review  N",#selector(nextReview)),status]);bottom.spacing=12
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.documentView=table
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("page")));table.headerView=nil;table.rowHeight=66;table.delegate=self;table.dataSource=self;table.allowsEmptySelection=false
        let tools=NSStackView();tools.orientation = .vertical;tools.alignment = .leading;tools.spacing=8
        let title=NSTextField(labelWithString:"CROP THE PHOTOGRAPH");title.font = .boldSystemFont(ofSize:13)
        detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor
        candidates.target=self;candidates.action=#selector(candidateChanged)
        previewButton.target=self;previewButton.action=#selector(togglePreview)
        [title,detail,button("Auto detect  D",#selector(detectCurrent)),candidates,previewButton,
         button("Rotate output  R",#selector(rotate)),button("Fit image  F",#selector(fit)),
         NSStackView(views:[button("Zoom +",#selector(zoomIn)),button("Zoom −",#selector(zoomOut))]),
         button("Previous crop  C",#selector(copyPrevious)),NSStackView(views:[button("Shrink  ;",#selector(shrinkCrop)),button("Expand  '",#selector(expandCrop))]),button("Full image  X",#selector(resetCrop)),
         NSStackView(views:[button("Undo Z",#selector(undo)),button("Redo Y",#selector(redo))]),
         NSStackView(views:[button("↖ 1",#selector(corner1)),button("↗ 2",#selector(corner2)),button("↙ 3",#selector(corner3)),button("↘ 4",#selector(corner4))])].forEach{tools.addArrangedSubview($0)}
        let hint=NSTextField(wrappingLabelWithString:"Drag a corner or any green edge.\nShift-drag a corner preserves angles.\nOption-drag moves the crop.\nDrag elsewhere to pan.\n\n1–4 select corners; 5–8 select edges. After pressing 1–8, arrow keys move the selection; Shift makes larger steps. Escape releases it.\nH/J/K/L expand left/bottom/top/right; Shift contracts. ; shrinks all; ' expands all.\n\nEvery proposal needs a visual check.")
        hint.font = .systemFont(ofSize:10);hint.textColor = .secondaryLabelColor;tools.addArrangedSubview(hint)
        for v in [top,bottom,scroll,canvas,tools] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo:root.topAnchor,constant:12),top.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:12),
            bottom.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-10),bottom.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:12),
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroll.topAnchor.constraint(equalTo:top.bottomAnchor,constant:12),scroll.bottomAnchor.constraint(equalTo:bottom.topAnchor,constant:-10),scroll.widthAnchor.constraint(equalToConstant:205),
            tools.bottomAnchor.constraint(lessThanOrEqualTo:canvas.bottomAnchor,constant:-8),
            tools.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-14),tools.topAnchor.constraint(equalTo:scroll.topAnchor,constant:12),tools.widthAnchor.constraint(equalToConstant:210),
            canvas.leadingAnchor.constraint(equalTo:scroll.trailingAnchor),canvas.trailingAnchor.constraint(equalTo:tools.leadingAnchor,constant:-12),canvas.topAnchor.constraint(equalTo:scroll.topAnchor),canvas.bottomAnchor.constraint(equalTo:scroll.bottomAnchor)])
    }
    func buildMenus(){
        let menu=NSMenu();let app=NSMenuItem();menu.addItem(app);let sub=NSMenu();app.submenu=sub
        sub.addItem(withTitle:"Keyboard shortcuts",action:#selector(help),keyEquivalent:"?").target=self
        sub.addItem(withTitle:"Quit PageCrop",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let edit=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"");menu.addItem(edit);edit.submenu=NSMenu(title:"Edit")
        for (title,action,key) in [("Undo",#selector(undo),"z"),("Redo",#selector(redo),"y"),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {let item=edit.submenu!.addItem(withTitle:title,action:action,keyEquivalent:key);if title=="Undo" || title=="Redo" {item.target=self}}
        NSApp.mainMenu=menu
    }
    func numberOfRows(in tableView:NSTableView)->Int {project.pages.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let p=project.pages[row],cell=NSTableCellView();let label=NSTextField(labelWithString:"\(row+1). \(URL(fileURLWithPath:p.path).lastPathComponent)\n\(p.reviewed ? "✓ Reviewed":p.status)")
        label.font = .systemFont(ofSize:11);label.lineBreakMode = .byTruncatingMiddle;label.frame=NSRect(x:57,y:12,width:140,height:40);cell.addSubview(label)
        let iv=NSImageView(frame:NSRect(x:5,y:7,width:46,height:50));iv.imageScaling = .scaleProportionallyUpOrDown;iv.image=thumbs.object(forKey:p.path as NSString);cell.addSubview(iv)
        if iv.image==nil && !thumbnailPending.contains(p.path) {
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
    func tableViewSelectionDidChange(_ notification:Notification){let row=table.selectedRow;if project.pages.indices.contains(row) {project.selected=row;loadCurrent()}}
    func selectCurrent(){guard let i=current else {canvas.placeholder=CropCanvas.emptyProjectMessage;canvas.image=nil;return};table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);table.scrollRowToVisible(i);loadCurrent()}
    func loadCurrent(){
        guard let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        original=nil;canvas.placeholder="";canvas.image=nil;canvas.preview=false;previewButton.state = .off;canvas.quad=p.quad;canvas.fit();refreshDetail()
        displayQueue.cancelAllOperations()
        displayQueue.addOperation{[weak self] in
            let result=Result {try Imaging.load(URL(fileURLWithPath:p.path),maxPixel:3200)}
            DispatchQueue.main.async {guard let self,self.displayToken==token else{return};switch result {case .success(let image):self.original=image;self.canvas.image=image;case .failure(let e):self.canvas.placeholder="Could not load this photograph";self.status.stringValue=e.localizedDescription}}
        }
    }
    func refreshDetail(){guard let i=current else{return};let p=project.pages[i]
        detail.stringValue="Photo \(i+1) of \(project.pages.count)\n\(URL(fileURLWithPath:p.path).lastPathComponent)\n\(p.reviewed ? "Reviewed":p.status)\nOutput rotation: \(p.rotation*90)°"
        candidates.removeAllItems();candidates.addItem(withTitle:"Choose proposal  [ / ]")
        for (j,c) in p.candidates.enumerated(){candidates.addItem(withTitle:"\(j+1) · \(c.source)")}
        if let selected=p.candidates.firstIndex(where:{$0.quad==p.quad}){candidates.selectItem(at:selected+1)}
        status.stringValue="\(project.pages.filter{$0.reviewed}.count)/\(project.pages.count) reviewed"
    }
    func save(){do{try project.save(projectURL);window?.title="PageCrop — \(projectURL.lastPathComponent)";if ProcessInfo.processInfo.environment["PAGECROP_TEST_DIR"] == nil {UserDefaults.standard.set(projectURL.path,forKey:"lastProject")}}catch{window?.title="PageCrop — SAVE FAILED — \(error.localizedDescription)";status.stringValue="SAVE FAILED: \(error.localizedDescription)"}}
    func edit(_ change:(inout Page)->Void){guard let i=current else{return};undoStack.append((project.pages[i].id,project.pages[i]));redoStack.removeAll();change(&project.pages[i]);project.pages[i].revision+=1;canvas.quad=project.pages[i].quad;save();refreshDetail();table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0));if canvas.preview{renderPreview()}}
    func navigate(_ d:Int){guard let i=current else{return};project.selected=min(project.pages.count-1,max(0,i+d));selectCurrent();save()}
    @objc func previous(){navigate(-1)}
    @objc func next(){navigate(1)}
    @objc func accept(){edit{$0.reviewed=true};navigate(1)}
    @objc func nextReview(){guard let i=current,!project.pages.isEmpty else{return};for d in 1...project.pages.count {let j=(i+d)%project.pages.count;if !project.pages[j].reviewed{project.selected=j;selectCurrent();return}}}
    @objc func fit(){canvas.fit()}
    @objc func zoomIn(){canvas.zoom=min(8,canvas.zoom*1.25)}
    @objc func zoomOut(){canvas.zoom=max(0.5,canvas.zoom/1.25)}
    @objc func rotate(){edit{$0.rotation=($0.rotation+1)%4};if !canvas.preview{previewButton.state = .on;togglePreview()}}
    @objc func resetCrop(){edit{$0.quad = .full;$0.status="Manual";$0.reviewed=false}}
    @objc func copyPrevious(){
        guard let i=current,i>0 else{return}
        let q=project.pages[i-1].quad
        edit{$0.quad=q;$0.status="Manual";$0.reviewed=false}
    }
    @objc func shrinkCrop(){resizeCrop(1/1.02)}
    @objc func expandCrop(){resizeCrop(1.02)}
    func resizeCrop(_ factor:Double){
        guard let i=current,let q=project.pages[i].quad.scaled(by:factor) else{return}
        if q != project.pages[i].quad {edit{$0.quad=q;$0.status="Manual";$0.reviewed=false}}
    }
    func resizeSide(_ key:String,inward:Bool){
        guard let i=current else{return}
        let edge=["h":3,"j":2,"k":0,"l":1][key]!
        let step=0.005*(inward ? -1.0:1.0)
        let delta=Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0)
        guard let q=project.pages[i].quad.movingEdge(edge,by:delta),q != project.pages[i].quad else{return}
        edit{$0.quad=q;$0.status="Manual";$0.reviewed=false}
    }
    @objc func undo(){guard let (id,old)=undoStack.popLast(),let i=project.pages.firstIndex(where:{$0.id==id}) else{return};redoStack.append((id,project.pages[i]));var restored=old;restored.revision=project.pages[i].revision+1;project.pages[i]=restored;project.selected=i;save();table.reloadData();selectCurrent()}
    @objc func redo(){guard let (id,old)=redoStack.popLast(),let i=project.pages.firstIndex(where:{$0.id==id}) else{return};undoStack.append((id,project.pages[i]));var restored=old;restored.revision=project.pages[i].revision+1;project.pages[i]=restored;project.selected=i;save();table.reloadData();selectCurrent()}
    @objc func togglePreview(){canvas.preview=previewButton.state == .on;if canvas.preview{renderPreview()}else{displayToken=UUID();canvas.image=original;canvas.fit()}}
    func renderPreview(){guard let image=original,let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        displayQueue.addOperation{[weak self] in let result=Result{try Imaging.corrected(image,quad:p.quad,rotation:p.rotation)};DispatchQueue.main.async {guard let self,self.displayToken==token,self.canvas.preview else{return};switch result{case .success(let output):self.canvas.image=output;self.canvas.fit();case .failure(let e):self.showError(e)}}}
    }
    @objc func candidateChanged(){guard let i=current else{return};let j=candidates.indexOfSelectedItem-1;guard project.pages[i].candidates.indices.contains(j) else{return};let q=project.pages[i].candidates[j].quad;edit{$0.quad=q;$0.status="Proposal selected";$0.reviewed=false}}
    func cycleCandidate(_ delta:Int){guard candidates.numberOfItems>1 else{return};let count=candidates.numberOfItems-1;let current=candidates.indexOfSelectedItem-1;let index=(current<0 ? (delta>0 ? 0:count-1):(current+delta+count)%count)+1;candidates.selectItem(at:index);candidateChanged();candidates.selectItem(at:index)}
    @objc func newProject(){
        save()
        let panel=NSSavePanel();panel.nameFieldStringValue="Book.pagecrop";panel.message="Choose where the new collection will autosave."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{let fresh=Project();try fresh.save(url);stop();project=fresh;projectURL=url;undoStack=[];redoStack=[];save();table.reloadData();canvas.placeholder=CropCanvas.emptyProjectMessage;canvas.image=nil;original=nil;detail.stringValue="Import photographs to begin";candidates.removeAllItems()}catch{showError(error)}
    }
    @objc func importImages(){
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true;panel.message="Choose photographs or a folder. Subfolders are not imported."
        guard panel.runModal() == .OK else{return}
        var urls:[URL]=[]
        for url in panel.urls {var directory:ObjCBool=false;if FileManager.default.fileExists(atPath:url.path,isDirectory:&directory),directory.boolValue {do{urls += try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)}catch{showError(error)}}else{urls.append(url)}}
        let supported=Set(["jpg","jpeg","png","tif","tiff","heic","heif","bmp"])
        let existing=Set(project.pages.map{$0.path});urls=urls.filter{supported.contains($0.pathExtension.lowercased()) && !existing.contains($0.path)}.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        project.pages += urls.map{Page(path:$0.path)};save();table.reloadData();selectCurrent();status.stringValue="Imported \(urls.count) photographs · B detects pending pages"
    }
    @objc func openProject(){let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"pagecrop") ?? .json,.json];guard panel.runModal() == .OK,let url=panel.url else{return};do{let loaded=try Project.read(url);stop();generation=UUID();project=loaded;project.selected=min(max(0,project.selected),max(0,project.pages.count-1));projectURL=url;save();undoStack=[];redoStack=[];thumbs.removeAllObjects();thumbnailPending=[];table.reloadData();selectCurrent()}catch{showError(error)}}
    @objc func saveAs(){let panel=NSSavePanel();panel.nameFieldStringValue="Book.pagecrop";guard panel.runModal() == .OK,let url=panel.url else{return};do{try project.save(url);projectURL=url;save();status.stringValue="Saved \(url.lastPathComponent)"}catch{showError(error)}}
    @objc func detectCurrent(){guard let i=current else{return};runDetection([i])}
    @objc func detectPending(){runDetection(project.pages.indices.filter{project.pages[$0].status=="Pending"})}
    func runDetection(_ indexes:[Int]){
        guard !detecting,!indexes.isEmpty else{return};detecting=true;let token=generation
        let snapshots=indexes.map{($0,project.pages[$0])}
        for (number,item) in snapshots.enumerated(){let (index,page)=item
            queue.addOperation{[weak self] in
                let result:Result<[Candidate],Error>=autoreleasepool{Result {try Detector().detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600))}}
                DispatchQueue.main.async {guard let self,self.generation==token else{return}
                    if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),self.project.pages[i].revision==page.revision {
                        switch result {
                        case .success(let found):
                            self.project.pages[i].candidates=found
                            if self.project.pages[i].status=="Pending" {
                                if let best=found.first {self.project.pages[i].quad=best.quad;self.project.pages[i].status="Check proposal"}else{self.project.pages[i].status="No boundary — crop manually"}
                            }
                        case .failure(let error):self.project.pages[i].status="Detection error";self.status.stringValue=error.localizedDescription
                        }
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:index),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.canvas.quad=self.project.pages[i].quad;self.refreshDetail()}
                    }
                    self.status.stringValue="Detection \(number+1)/\(snapshots.count) · review every proposal"
                    if number==snapshots.count-1 {self.detecting=false}
                }
            }
        }
    }
    @objc func stop(){queue.cancelAllOperations();generation=UUID();thumbnailPending=[];detecting=false;exportCancelled=true;status.stringValue="Stopped; completed edits are saved"}
    @objc func exportImages(){guard !exporting,!project.pages.isEmpty else{return};let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.canCreateDirectories=true;panel.message="Choose a destination. A new dated subfolder will contain full-resolution corrected JPEGs for all pages, including unreviewed pages.";guard panel.runModal() == .OK,let parent=panel.url else{return}
        let folder=parent.appendingPathComponent("PageCrop-"+ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")+"-"+UUID().uuidString.prefix(6))
        do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}catch{showError(error);return}
        let pages=project.pages;exportCancelled=false;exporting=true
        exportQueue.addOperation{[weak self] in
            var completed=0
            do{
                for (i,page) in pages.enumerated(){let cancelled=DispatchQueue.main.sync{self?.exportCancelled ?? true};if cancelled{break}
                    try autoreleasepool{
                        let name=String(format:"%04d-",i+1)+URL(fileURLWithPath:page.path).deletingPathExtension().lastPathComponent+".jpg"
                        let temp=folder.appendingPathComponent(".partial-\(i).jpg"),dest=folder.appendingPathComponent(name)
                        do{try Imaging.export(page,to:temp);try FileManager.default.moveItem(at:temp,to:dest)}catch{try? FileManager.default.removeItem(at:temp);throw error}
                    };completed+=1
                    let done=completed;DispatchQueue.main.async{self?.status.stringValue="Exported \(done)/\(pages.count)"}
                }
                let done=completed;DispatchQueue.main.async{self?.exporting=false;self?.status.stringValue="Exported \(done)/\(pages.count) to \(folder.lastPathComponent)";NSWorkspace.shared.open(folder)}
            }catch{DispatchQueue.main.async{self?.exporting=false;self?.showError(error)}}
        }
    }
    func showError(_ error:Error){let alert=NSAlert(error:error);alert.runModal()}
    @objc func corner1(){selectCorner(0)}
    @objc func corner2(){selectCorner(1)}
    @objc func corner3(){selectCorner(3)}
    @objc func corner4(){selectCorner(2)}
    func selectCorner(_ i:Int,keyboard:Bool=false){if canvas.preview{previewButton.state = .off;togglePreview()};canvas.selectCorner(i,keyboard:keyboard);window.makeFirstResponder(canvas)}
    func handleKey(_ e:NSEvent)->Bool {
        guard !e.modifierFlags.contains(.command),!e.modifierFlags.contains(.control),let key=e.charactersIgnoringModifiers?.lowercased() else{return false}
        if [123,124,125,126].contains(e.keyCode),canvas.keyboardSelection {let mapping:[UInt16:String]=[123:"a",124:"d",125:"s",126:"w"];canvas.nudge(mapping[e.keyCode]!,large:e.modifierFlags.contains(.shift));return true}
        if ["h","j","k","l"].contains(key) {
            if e.modifierFlags.contains(.option) {
                guard let i=current else{return true}
                let step=e.modifierFlags.contains(.shift) ? 0.02:0.005
                let delta=Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0)
                if let q=project.pages[i].quad.translated(by:delta),q != project.pages[i].quad {
                    edit{$0.quad=q;$0.status="Manual";$0.reviewed=false}
                }
            } else {resizeSide(key,inward:e.modifierFlags.contains(.shift))}
            return true
        }
        switch key {
        case "g":newProject();case "i":importImages();case "o":openProject();case "s":saveAs();case "d":detectCurrent();case "b":detectPending();case "e":exportImages()
        case "p":previewButton.state=previewButton.state == .on ? .off:.on;togglePreview()
        case "r":rotate();case "f","0":fit();case "+","=":zoomIn();case "-":zoomOut();case "c":copyPrevious();case ";":shrinkCrop();case "'":expandCrop();case "x":resetCrop();case "z":undo();case "y":redo();case "n":nextReview();case "[":cycleCandidate(-1);case "]":cycleCandidate(1)
        case "1","2","3","4":selectCorner([0,1,3,2][Int(key)!-1],keyboard:true)
        case "5","6","7","8":if canvas.preview{previewButton.state = .off;togglePreview()};canvas.selectEdge([0,3,1,2][Int(key)!-5],keyboard:true);window.makeFirstResponder(canvas)
        case "?","/":help()
        default:
            if e.keyCode==53 {if canvas.hasSelection{canvas.releaseCorner()}else{stop()}}
            else if e.keyCode==123 {navigate(-1)}else if e.keyCode==124{navigate(1)}else if e.keyCode==36{accept()}
            else if e.keyCode==115 {project.selected=0;selectCurrent()}else if e.keyCode==119{project.selected=max(0,project.pages.count-1);selectCurrent()}
            else if e.keyCode==116{navigate(-10)}else if e.keyCode==121{navigate(10)}else{return false}
        }
        return true
    }
    @objc func help(){let alert=NSAlert();alert.messageText="PageCrop keyboard shortcuts";alert.informativeText="G New project    I Import photographs    O Open project    S Save project as\nD Detect current    B Detect pending    Esc Stop work / release corner\n← / → Previous / next    Return Accept and next    N Next unreviewed\nHome / End First / last    Page Up / Down Move ten photos\n[ / ] Previous / next crop proposal\n1 2 3 4 Select top-left, top-right, bottom-left, bottom-right corner\n5 6 7 8 Select top, left, right, bottom edge\nArrow keys Nudge selected corner or edge    Shift Larger nudge\nH J K L Expand left, bottom, top, right edge; Shift contracts that edge\nOption + H J K L Move whole crop left, down, up, right; Shift moves farther\nP Corrected preview    R Rotate output clockwise\n+ / − Zoom    F or 0 Fit    C Copy previous crop    ; Shrink crop    ' Expand crop    X Full image\nZ Undo    Y Redo    E Export all corrected JPEGs    ? This reference\n\nOnly selecting with 1–8 makes arrow keys move a corner or edge. Mouse selection keeps arrow navigation. Escape releases it and restores arrow-key navigation. Single-key shortcuts are disabled while typing in text fields. Shift-drag a corner preserves side angles and fixes the opposite corner. Drag any green edge to move both endpoints. The corner magnifier hides on mouse release. Drag the image to pan; Option-drag moves the crop. All main actions also have buttons. Originals are never modified.";alert.runModal()}
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=AppDelegate()
app.delegate=delegate
app.run()

import AppKit
import CropCore
import UniformTypeIdentifiers

/// Page snapshots restore edits; a structure snapshot restores the whole page list after reordering or removal.
/// What `saveBadExample` writes beside the photograph.
struct BadExample: Encodable {
    var saved: Date
    var app: String
    var photograph: String
    var number: Int
    var of: Int
    var note: String
    var page: Page
    /// The page before it in the project, whose split guides this one's.
    var previous: Page?
    var splitGuide: PageSplit?
}
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
    /// Named sets of image settings kept on this Mac, and the menu they are chosen from.
    var presets:[SettingsPreset]=PresetStore.decode(UserDefaults.standard.data(forKey:PresetStore.key))
    let presetPopup=NSPopUpButton(frame:.zero,pullsDown:true)
    /// How often each preset has been applied, which decides the three that get ⌘1, ⌘2 and ⌘3.
    var presetUses=UserDefaults.standard.dictionary(forKey:PresetStore.usesKey) as? [String:Int] ?? [:]
    /// Tools ▸ Apply Preset to Selected Pages, kept filled so that its shortcuts work without the menu being opened.
    let toolsPresetMenu=NSMenu(title:"Apply Preset to Selected Pages")
    let brightnessSlider=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    let contrastSlider=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil)
    let sharpnessSlider=NSSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    let exposureSlider=NSSlider(value:0,minValue:-1,maxValue:1,target:nil,action:nil),exposureValue=NSTextField(labelWithString:"0")
    /// The brush for the next stroke: half its width as a fraction of the photograph's longer side, and how heavily it blurs.
    let smudgeSizeSlider=NSSlider(value:0.02,minValue:0.005,maxValue:0.08,target:nil,action:nil)
    let smudgeStrengthSlider=NSSlider(value:0.5,minValue:0,maxValue:1,target:nil,action:nil)
    let smudgeSizeValue=NSTextField(labelWithString:""),smudgeStrengthValue=NSTextField(labelWithString:"")
    let smudgeButton=NSButton(),clearSmudgeButton=NSButton(),cloneButton=NSButton(),clearCloneButton=NSButton()
    /// How much grain the next smudges get, and its value label.
    let smudgeGrainSlider=NSSlider(value:Imaging.smudgeGrain,minValue:0,maxValue:1,target:nil,action:nil),smudgeGrainValue=NSTextField(labelWithString:"")
    var smudgeRows:[NSGridRow]=[],brushRow:NSGridRow?
    /// On a split spread, which page the deskew commands act on: both, the left or the right.
    let deskewHalf=NSSegmentedControl(labels:["Both","Left","Right"],trackingMode:.selectOne,target:nil,action:nil)
    var deskewHalfRow:NSGridRow?
    /// The part the deskew commands act on, or nil for all: a choice only a split spread on screen offers.
    var deskewPart:Int? {
        guard let i=current,Exporter.previewParts(project.pages[i])==2,deskewHalf.selectedSegment>0 else{return nil}
        return deskewHalf.selectedSegment-1
    }
    static let halfNames=["both pages","the left page","the right page"]
    @objc func deskewHalfChanged(){
        status.stringValue="Deskew now acts on \(AppDelegate.halfNames[max(0,deskewHalf.selectedSegment)])"
    }
    @objc func nextDeskewHalf(){
        guard let i=current,Exporter.previewParts(project.pages[i])==2 else{status.stringValue="Split the page first to deskew its two pages separately";NSSound.beep();return}
        deskewHalf.selectedSegment=(max(0,deskewHalf.selectedSegment)+1)%3;deskewHalfChanged()
    }
    let brightnessValue=NSTextField(labelWithString:"0"),contrastValue=NSTextField(labelWithString:"0"),sharpnessValue=NSTextField(labelWithString:"0")
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
    /// Changes to a project file that have not been written to it yet.
    var unsaved=false
    /// True once an untitled session has been changed since it was started or opened.
    var untitledChanged=false
    var autosaveTimer: Timer?
    var exportCancelled=false
    var exporting=false
    var reviewing=false
    var reviewCancelled=false
    /// The request a second opinion is waiting on, kept so that Stop can cancel it.
    var reviewTask: URLSessionTask?
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
    /// The pages whose image settings a run of slider changes has touched, so their rows are redrawn when it is
    /// recorded, whatever is selected by then.
    var adjustedPages=Set<UUID>()
    /// How many times in a row a page's preview picture could not be made, with the settings it was for.
    var previewFailures:[UUID:(look:String,count:Int)]=[:]
    var reloading=false
    /// Decoded photographs around the one on screen, by path, and the way the user last stepped.
    var decoded:[String:CGImage]=[:]
    var travel=1
    var importing=false
    let applyAllButton=NSButton(title:"Apply Settings to All Pages",target:nil,action:nil)
    let banner=NSVisualEffectView(),bannerLabel=NSTextField(labelWithString:""),bannerSpinner=NSProgressIndicator()
    var shownSize=(width:0.0,height:0.0)
    var copiedSettings: (Adjustments?,PageFormat?)?
    var copiedRotation: Int?
    var pixelSizes: [String:CGSize]=[:]
    var exportOptions=ExportOptions()
    var exportSheet: ExportSheetController?
    var settings: SettingsController?
    var recovery: RecoveryController?
    /// What this run is doing, written to the support folder as it changes so that a launch after a crash can tell.
    var journal=CrashJournal()
    let journalLock=NSLock()
    /// A test run keeps no journal, unless it is the test of the journal itself.
    lazy var journalKept=testDirectory == nil || ProcessInfo.processInfo.environment["KETTLESTITCH_TEST_JOURNAL"] != nil
    /// The journal a crashed run left behind, as it was found at launch.
    var crashFound: CrashJournal?
    /// The incomplete files named by the last import.
    var incompleteNames:[String]=[]
    /// Saved settings found unreadable at launch and kept under another name.
    var settingsSetAside:[String]=[]
    /// Edit ▸ Image Settings Preset, filled each time it opens.
    let presetMenu=NSMenu(title:"Image Settings Preset")
    /// The app's folder in Application Support, or the test folder.
    var supportURL: URL!
    /// Names this session's recovery copy. A new one is taken whenever another project is opened.
    var sessionID=UUID()
    /// What went wrong the last time the project could not be written, shown until a write succeeds.
    var saveFailure: String?
    var shortcuts: ShortcutsController?
    /// Which key runs which command: the defaults with the user's changes, made in Settings ▸ Shortcuts.
    /// A test run starts from the default keys and keeps nothing, so one that stops half way leaves no trace.
    lazy var keyBindings=testDirectory == nil ? KeyBindings.decode(UserDefaults.standard.data(forKey:KeyBindings.key)):KeyBindings()
    /// The key and action labels of the inspector's short list, updated when a key changes.
    var shortcutKeyLabels:[(NSTextField,NSTextField)]=[]
    var usageLog: UsageLogController?
    /// The candidates the last split proposal for each page came with, and which of them is showing.
    var splitOptions:[UUID:(options:[PageSplit],index:Int,quad:Quad,rotation:Int)]=[:]
    var badExampleItem: NSMenuItem?,badExampleSeparator: NSMenuItem?
    /// Where the history of requests to Claude is kept.
    var usageURL=URL(fileURLWithPath:"/dev/null")
    var shortcutMonitor: Any?
    /// Sidebar pictures by photograph, and by page as the preview shows them. See `trimThumbnails`.
    var thumbs:[String:NSImage]=[:]
    var previewThumbs:[UUID:PreviewThumbnail]=[:]
    /// Photographs' pictures turned for rotated pages, by path and number of quarter turns.
    var turnedThumbs:[String:NSImage]=[:]
    /// When each picture was asked for, how often loading one has failed, and how many times the regular check
    /// had to put a blank row right.
    var thumbnailPending:[String:Date]=[:]
    var thumbnailFailures:[String:Int]=[:]
    var previewPending=Set<UUID>()
    var thumbnailRecoveries=0
    var thumbnailTimer: Timer?
    var sidebarLayoutItem: NSToolbarItem?,sidebarLayoutMenuItem: NSMenuItem?
    /// The toolbar button shows the layout it switches to.
    var sidebarLayoutSymbol: NSImage? {ThumbnailPolicy.large ? symbol("list.bullet","sidebar.left"):symbol("square.grid.2x2","photo")}
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
        thumbnailQueue.maxConcurrentOperationCount=3;thumbnailQueue.qualityOfService = .utility
        let library=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        let support=testDirectory.map{URL(fileURLWithPath:$0)} ?? library.appendingPathComponent("KettleStitch")
        if testDirectory == nil {carryOverLegacyData(in:library,to:support)}
        do {try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)} catch {showError(error)}
        supportURL=support
        // What the last run left behind is read before this run begins its own journal.
        if journalKept {
            crashFound=CrashJournal.read(in:support);try? journal.write(in:support)
            Imaging.readingChanged={[weak self] paths in self?.updateJournal{$0.reading=paths}}
        }
        if testDirectory == nil {
            // Saved presets or keys that cannot be read are set aside under another name, not written over.
            for (key,unreadable) in [(PresetStore.key,PresetStore.isUnreadable),(KeyBindings.key,KeyBindings.isUnreadable)] {
                if let data=UserDefaults.standard.data(forKey:key),unreadable(data) {UserDefaults.standard.set(data,forKey:key+".unreadable");UserDefaults.standard.removeObject(forKey:key);settingsSetAside.append(key==PresetStore.key ? "presets":"shortcut changes")}
            }
        }
        // The app opens empty. Each session gets its own untitled file, so unnamed work from an earlier
        // session is never overwritten; it stays reachable under File ▸ Open Recent.
        projectURL=support.appendingPathComponent(LaunchPolicy.untitledName(Date()))
        // Another copy of the app begun in the same second has that name; this session takes one of its own.
        if FileManager.default.fileExists(atPath:projectURL.path) {projectURL=support.appendingPathComponent(LaunchPolicy.untitledName(Date(),unique:String(UUID().uuidString.prefix(4))))}
        usageURL=support.appendingPathComponent(UsageLog.fileName)
        if let asked=LaunchPolicy.projectToOpen(arguments:CommandLine.arguments,testDirectory:testDirectory),FileManager.default.fileExists(atPath:asked.path) {
            do {project=try Project.read(asked);project.selected=min(max(0,project.selected),max(0,project.pages.count-1));projectURL=asked} catch {showError(error)}
        }
        if let data=UserDefaults.standard.data(forKey:"exportOptions"),let saved=try? JSONDecoder().decode(ExportOptions.self,from:data) {exportOptions=saved}
        Keychain.noteLaunch();Imaging.pictureZoneMode=SettingsController.zoneMode
        ThumbnailPolicy.large=UserDefaults.standard.bool(forKey:"sidebarLargePictures")
        buildUI();buildMenus();applyKeyBindings();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        canvas.onCommit={[weak self] q in self?.edit{$0.setManualCrop(q)}}
        canvas.onSplitCommit={[weak self] s in self?.edit(geometry:false){$0.split=s;$0.splitByHand=true}}
        canvas.onZoneCommit={[weak self] z in self?.edit(geometry:false){$0.pictureZones=($0.pictureZones ?? [])+[z]};self?.zoneDrawn()}
        canvas.onSmudgeCommit={[weak self] points in guard let self else{return};let radius=self.smudgeSizeSlider.doubleValue,strength=self.smudgeStrengthSlider.doubleValue,grain=self.smudgeGrainSlider.doubleValue
            self.edit(geometry:false){$0.smudges=($0.smudges ?? [])+[Smudge(points:points,radius:radius,strength:strength,grain:grain)]}
            self.status.stringValue="Smudged · keep painting, Command-Z undoes a stroke, Escape puts the brush down"
        }
        canvas.onCloneCommit={[weak self] points,offset in guard let self else{return};let radius=self.smudgeSizeSlider.doubleValue
            self.edit(geometry:false){$0.clones=($0.clones ?? [])+[CloneStroke(points:points,radius:radius,offset:offset)]}
            self.status.stringValue="Cloned · keep painting from the same place, Option-click for another, Command-Z undoes a stroke"
        }
        canvas.onCloneSource={[weak self] chosen in
            if !chosen {NSSound.beep()}
            self?.status.stringValue=chosen ? "Copying from here · now drag where the copy should go":"Option-click the place to copy from first"
        }
        canvas.onZoneRemove={[weak self] i in self?.edit(geometry:false){$0.pictureZones?.remove(at:i);if $0.pictureZones?.isEmpty==true{$0.pictureZones=nil}}}
        canvas.onNavigate={[weak self] delta in self?.navigate(delta)}
        canvas.onAccept={[weak self] in self?.accept()}
        canvas.onUndo={[weak self] in self?.undo()}
        shortcutMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self, NSApp.keyWindow===self.window, !(self.window.firstResponder is NSTextView), !(self.window.firstResponder is NSTextField) else {return event}
            return self.handleKey(event) ? nil:event
        }
        reloadPages();selectCurrent();updateTitle()
        UserDefaults.standard.register(defaults:[SettingsController.autosaveKey:true])
        thumbnailTimer=Timer.scheduledTimer(withTimeInterval:ThumbnailPolicy.checkInterval,repeats:true){[weak self] _ in self?.checkThumbnails()}
        autosaveTimer=Timer.scheduledTimer(withTimeInterval:LaunchPolicy.autosaveInterval,repeats:true){[weak self] _ in
            guard let self,LaunchPolicy.shouldAutosave(enabled:UserDefaults.standard.bool(forKey:SettingsController.autosaveKey),hasProjectFile:self.hasProjectFile,unsaved:self.unsaved) else{return}
            if self.write() {self.status.stringValue="Auto-saved \(self.projectURL.lastPathComponent)"}
        }
        status.stringValue=project.pages.isEmpty ? "Drop photographs here, or choose File ▸ Import Photographs":"Press ? for keyboard shortcuts"
        checkForUpdatesAtStartup()
        if !settingsSetAside.isEmpty {status.stringValue="Your saved \(settingsSetAside.joined(separator:" and ")) could not be read and were set aside; the app starts without them"}
        DispatchQueue.main.async{if let found=self.crashFound {self.handleCrash(found)};self.offerRecovery()}
        window.delegate=self;window.registerForDraggedTypes([.fileURL])
        let waiting=pendingOpen;pendingOpen=[];if !waiting.isEmpty {receive(waiting)} else if !project.pages.isEmpty {DispatchQueue.main.async{self.findMissingPhotographs()}}
        // Test hook for files handed over by the system at launch: report what arrived, then quit.
        if testDirectory != nil,let report=ProcessInfo.processInfo.environment["KETTLESTITCH_REPORT"] {
            DispatchQueue.main.asyncAfter(deadline:.now()+2){
                try? "pages=\(self.project.pages.count) title=\(self.window.title) status=\(self.status.stringValue) held=\(Imaging.heldCount)\n".write(toFile:report,atomically:true,encoding:.utf8);NSApp.terminate(nil)
            }
        }
        if let folder=ProcessInfo.processInfo.environment["KETTLESTITCH_SMOKE_FOLDER"],let other=ProcessInfo.processInfo.environment["KETTLESTITCH_SMOKE_PROJECT"],let dir=testDirectory {runEmptySmoke(dir,folder:URL(fileURLWithPath:folder),project:URL(fileURLWithPath:other))}
        if CommandLine.arguments.contains("--smoke"),let dir=testDirectory {runSmoke(dir)}
        if CommandLine.arguments.contains("--bench"),testDirectory != nil {runBench()}
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
    /// Coming back to the app, photographs that could not be read are tried again: a file that was missing or cut
    /// short may have been copied again meanwhile.
    func applicationDidBecomeActive(_ notification: Notification){
        guard window != nil,!thumbnailFailures.isEmpty || (current != nil && original == nil) else{return}
        let failed=Set(thumbnailFailures.keys);thumbnailFailures=[:]
        let rows=IndexSet(project.pages.indices.filter{failed.contains(project.pages[$0].path)})
        table.reloadData(forRowIndexes:rows,columnIndexes:IndexSet(integer:0))
        if current != nil,original == nil {loadCurrent()}
    }
    func applicationShouldTerminate(_ sender: NSApplication)->NSApplication.TerminateReply {confirmUnsaved(leaving:true) ? .terminateNow:.terminateCancel}
    func applicationWillTerminate(_ notification: Notification){
        queue.cancelAllOperations();reviewTask?.cancel();commitAdjustments();writeUntitled();writeRecoveryCopy()
        // A proper quit leaves no journal; one found at the next launch then means a crash.
        Imaging.readingChanged=nil;journalLock.lock();if journalKept {CrashJournal.clear(in:supportURL)};journalLock.unlock()
    }

    // MARK: Page list
    func numberOfRows(in tableView:NSTableView)->Int {project.pages.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let p=project.pages[row]
        let cell=(tableView.makeView(withIdentifier:PageCell.identifier,owner:nil) as? PageCell) ?? PageCell()
        cell.large=ThumbnailPolicy.large
        let picture=thumbnail(p)
        cell.show(p,number:row+1,thumbnail:picture,unusual:deviationRows.indices.contains(row) ? deviationRows[row].reason:nil,review:ReviewProgress.state(p.id,active:reviewActive,pending:reviewPending))
        // No picture yet: ask for it, or say plainly that the photograph cannot be read, so a row is never just blank.
        if picture == nil {
            if thumbnailUnreadable(p.path) {cell.showUnreadable()} else {requestThumbnail(p.path)}
        }
        return cell
    }
    @objc func toggleSidebarLayout(){setSidebarLarge(!ThumbnailPolicy.large)}
    /// Switches the sidebar between compact rows and large pictures with the name beneath. The pictures are of a
    /// different size in each, so they are loaded again.
    func setSidebarLarge(_ on:Bool){
        ThumbnailPolicy.large=on;UserDefaults.standard.set(on,forKey:"sidebarLargePictures")
        thumbs=[:];previewThumbs=[:];turnedThumbs=[:];thumbnailFailures=[:]
        table.rowHeight=ThumbnailPolicy.rowHeight
        let selected=table.selectedRowIndexes
        reloadPages()
        reloading=true;table.selectRowIndexes(selected,byExtendingSelection:false);reloading=false
        if let i=current {table.scrollRowToVisible(i)}
        sidebarLayoutItem?.image=sidebarLayoutSymbol;sidebarLayoutMenuItem?.state=on ? .on:.off
        status.stringValue=on ? "Sidebar shows large pictures":"Sidebar shows compact rows"
    }
    // MARK: Reordering pages
    static let rowType=NSPasteboard.PasteboardType("local.kettlestitch.sidebar-row")
    /// Dragging rows in the sidebar reorders the pages. A row carries only its number; the order is saved with the project.
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {
        guard MenuPolicy.isEnabled(.reversePages,menuState) else{return nil}
        let item=NSPasteboardItem();item.setString(String(row),forType:AppDelegate.rowType);return item
    }
    func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
        guard info.draggingSource as? NSTableView === table,info.draggingPasteboard.availableType(from:[AppDelegate.rowType]) != nil else{return []}
        // Pages go between rows, never onto one.
        tableView.setDropRow(row,dropOperation:.above);return .move
    }
    func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation:NSTableView.DropOperation)->Bool {
        let rows=IndexSet((info.draggingPasteboard.pasteboardItems ?? []).compactMap{$0.string(forType:AppDelegate.rowType)}.compactMap(Int.init))
        return movePages(rows,to:row)
    }
    /// Moves pages to before row `destination`, as one change that Undo reverses. The photograph on screen stays on
    /// screen, and the moved pages are left selected.
    @discardableResult func movePages(_ rows:IndexSet,to destination:Int)->Bool {
        let moved=Project.moving(project.pages,rows:rows,to:destination)
        guard moved.map({$0.id}) != project.pages.map({$0.id}) else{return false}
        let shown=current.map{project.pages[$0].id},ids=Set(rows.filter{project.pages.indices.contains($0)}.map{project.pages[$0].id})
        restructure{project.pages=moved;if let shown,let i=moved.firstIndex(where:{$0.id==shown}) {project.selected=i}}
        let now=IndexSet(project.pages.indices.filter{ids.contains(project.pages[$0].id)})
        if now.contains(project.selected) {reloading=true;table.selectRowIndexes(now,byExtendingSelection:false);reloading=false}
        status.stringValue="Moved \(ids.count) page\(ids.count==1 ? "":"s") · Undo puts \(ids.count==1 ? "it":"them") back"
        return true
    }
    @objc func movePagesUp(){let rows=IndexSet(targetIndexes);guard let first=rows.first,first>0 else{NSSound.beep();return};movePages(rows,to:first-1)}
    @objc func movePagesDown(){let rows=IndexSet(targetIndexes);guard let last=rows.last,last<project.pages.count-1 else{NSSound.beep();return};movePages(rows,to:last+2)}
    /// True when the photograph is missing, or has failed to load as often as is worth trying.
    func thumbnailUnreadable(_ path:String)->Bool {
        (thumbnailFailures[path] ?? 0)>=ThumbnailPolicy.attempts || !FileManager.default.fileExists(atPath:path)
    }
    /// Loads a photograph's sidebar picture in the background. A picture belongs to its file, not to the page list
    /// as it was when asked for: it is kept whatever has been removed, reordered or stopped since, and shown in
    /// whichever rows now hold that photograph. A load that fails is tried again a little later.
    func requestThumbnail(_ path:String){
        guard thumbnailPending[path] == nil else{return}
        thumbnailPending[path]=Date()
        thumbnailQueue.addOperation{[weak self] in
            let image=try? Imaging.load(URL(fileURLWithPath:path),maxPixel:ThumbnailPolicy.plainPixels)
            DispatchQueue.main.async {guard let self else{return};self.thumbnailPending[path]=nil
                if let image {
                    self.thumbnailFailures[path]=nil
                    self.thumbs[path]=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
                    self.turnedThumbs=self.turnedThumbs.filter{!$0.key.hasPrefix(path+"#")}
                    self.trimThumbnails();self.reloadRows(showing:path)
                } else {
                    let failures=(self.thumbnailFailures[path] ?? 0)+1;self.thumbnailFailures[path]=failures
                    // Reloading the row asks again, or shows the mark for a photograph that cannot be read.
                    DispatchQueue.main.asyncAfter(deadline:.now()+ThumbnailPolicy.retryDelay(after:failures)){[weak self] in self?.reloadRows(showing:path)}
                }
            }
        }
    }
    func reloadRows(showing path:String){
        let rows=IndexSet(project.pages.indices.filter{project.pages[$0].path==path})
        if !rows.isEmpty {table.reloadData(forRowIndexes:rows,columnIndexes:IndexSet(integer:0))}
    }
    /// Sidebar pictures are held firmly, not in a cache the system may empty when memory is short: an emptied cache
    /// showed as rows going blank. They are small, and only a very long book has any dropped, farthest pages first.
    func trimThumbnails(){
        guard thumbs.count>ThumbnailPolicy.kept || previewThumbs.count>ThumbnailPolicy.kept else{return}
        let visible=table.rows(in:table.visibleRect),centre=visible.location+visible.length/2
        let order=project.pages.indices.sorted{abs($0-centre)<abs($1-centre)}.prefix(ThumbnailPolicy.kept*3/4)
        let paths=Set(order.map{project.pages[$0].path}),ids=Set(order.map{project.pages[$0].id})
        thumbs=thumbs.filter{paths.contains($0.key)};previewThumbs=previewThumbs.filter{ids.contains($0.key)};turnedThumbs=[:]
    }
    /// The sidebar picture for a page: the photograph, or in preview what export will make of it.
    func thumbnail(_ p:Page)->NSImage? {
        guard let plain=thumbs[p.path] else{return nil}
        // Outside the preview the photograph is shown turned as the page is, like the canvas.
        guard canvas.preview else{return turned(plain,for:p)}
        let look=PreviewThumbnail.look(p),made=previewThumbs[p.id]
        if let made,made.look==look {return made.image}
        if !previewPending.contains(p.id) {
            previewPending.insert(p.id);let small=plain.cgImage(forProposedRect:nil,context:nil,hints:nil)
            thumbnailQueue.addOperation{[weak self] in
                // Cleanup is tuned for print at reading size: worked on the tiny sidebar picture it wipes a page of
                // text to plain white, which looked as if the picture had gone. So the preview is made from a
                // larger copy of the photograph and then reduced.
                let source=(try? Imaging.load(URL(fileURLWithPath:p.path),maxPixel:ThumbnailPolicy.previewSourcePixels)) ?? small
                let image=source.flatMap{try? Exporter.preview($0,page:p)}.map{ThumbnailPolicy.reduced($0,to:ThumbnailPolicy.previewPixels)}
                DispatchQueue.main.async {guard let self else{return};self.previewPending.remove(p.id)
                    guard let image else{self.previewFailures[p.id]=(look,(self.previewFailures[p.id]?.look==look ? self.previewFailures[p.id]!.count:0)+1);return}
                    self.previewFailures[p.id]=nil
                    self.previewThumbs[p.id]=PreviewThumbnail(NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)),look)
                    self.trimThumbnails()
                    if let row=self.project.pages.firstIndex(where:{$0.id==p.id}) {self.table.reloadData(forRowIndexes:IndexSet(integer:row),columnIndexes:IndexSet(integer:0))}
                }
            }
        }
        // The last rendering stands in until the new one is ready.
        return made?.image ?? plain
    }
    /// The photograph's picture turned by the page's rotation, made once for each turn and kept.
    func turned(_ plain:NSImage,for p:Page)->NSImage {
        let turn=ViewTurn(p.rotation);guard turn.quarterTurns != 0 else{return plain}
        let key="\(p.path)#\(turn.quarterTurns)"
        if let made=turnedThumbs[key] {return made}
        let made=ThumbnailPolicy.turned(plain,by:turn);turnedThumbs[key]=made;return made
    }
    /// Looks at the rows on screen every couple of seconds. A row with no picture and nothing under way to get one
    /// is asked for again, and a request that never came back is forgotten so that it can be made anew.
    func checkThumbnails(){
        guard window.isVisible,!project.pages.isEmpty else{return}
        for (path,asked) in thumbnailPending where Date().timeIntervalSince(asked)>ThumbnailPolicy.patience && thumbnailQueue.operationCount==0 {
            thumbnailPending[path]=nil;thumbnailRecoveries+=1
        }
        let visible=table.rows(in:table.visibleRect);var blank=IndexSet()
        for row in visible.location..<NSMaxRange(visible) where project.pages.indices.contains(row) {
            guard let cell=table.view(atColumn:0,row:row,makeIfNecessary:false) as? PageCell else{continue}
            let path=project.pages[row].path
            // Blank with nothing coming, or still marked unreadable though the picture has since arrived.
            if cell.thumb.image == nil ? thumbnailPending[path] == nil:(cell.unreadable && thumbs[path] != nil) {blank.insert(row)}
            // In the preview, a picture made for settings the page no longer has, with no new one on its way.
            else if canvas.preview,thumbs[path] != nil {
                let page=project.pages[row],look=PreviewThumbnail.look(page),made=previewThumbs[page.id]
                let givenUp=previewFailures[page.id].map{$0.look==look && $0.count>=ThumbnailPolicy.previewAttempts} ?? false
                if !previewPending.contains(page.id),!givenUp,made?.look != look || cell.thumb.image !== made?.image {blank.insert(row)}
            }
        }
        guard !blank.isEmpty else{return}
        thumbnailRecoveries+=blank.count
        table.reloadData(forRowIndexes:blank,columnIndexes:IndexSet(integer:0))
    }
    /// A full reload resets the table's selection; that must not change the photograph on screen.
    func reloadPages(){reloading=true;table.reloadData();reloading=false}
    func tableViewSelectionDidChange(_ notification:Notification){
        guard !reloading else{return}
        // A slider change still waiting to be recorded belongs to the pages that were selected.
        commitAdjustments()
        // Extending the selection keeps the photograph on screen.
        let row=table.selectedRow
        guard project.pages.indices.contains(row),!table.selectedRowIndexes.contains(project.selected) || table.selectedRowIndexes.count==1 else{return}
        if row != project.selected || original==nil {project.selected=row;loadCurrent()}
    }
    func selectCurrent(){
        guard let i=current else {displayToken=UUID();original=nil;canvas.placeholder=CropCanvas.emptyProjectMessage;canvas.image=nil;refreshDetail();return}
        // Selecting the row would otherwise start a load of its own beside the one below.
        reloading=true;table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);reloading=false
        table.scrollRowToVisible(i);loadCurrent()
    }
    func loadCurrent(){
        guard let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        original=nil;canvas.placeholder="";canvas.image=nil;canvas.quad=p.quad;canvas.fit();canvas.forgetCloneSource();refreshDetail()
        displayQueue.cancelAllOperations()
        // A neighbour of the last photograph is usually decoded already.
        if let ready=decoded[p.path] {present(ready);readAhead(from:i);return}
        displayQueue.addOperation{[weak self] in
            // It may have been read ahead while this waited its turn.
            let ready=DispatchQueue.main.sync{self?.decoded[p.path]}
            let result=ready.map{Result<CGImage,Error>.success($0)} ?? Result {try Imaging.load(URL(fileURLWithPath:p.path),maxPixel:3200)}
            DispatchQueue.main.async {guard let self,self.displayToken==token else{return};switch result {case .success(let image):self.decoded[p.path]=image;self.present(image);self.readAhead(from:i);case .failure(let e):
                // An incomplete file says so on the canvas: looking for it elsewhere would not help.
                let cutShort=Imaging.incomplete(URL(fileURLWithPath:p.path)) != nil
                self.canvas.placeholder=Imaging.isHeld(p.path) ? "This photograph was set aside after KettleStitch closed unexpectedly\nFile ▸ Try Set-Aside Photographs Again reads it once more":cutShort ? "This photograph’s file is incomplete\nCopy it again from where it came, to the same place":"Could not load this photograph\nFile ▸ Locate Missing Photographs… finds moved files";self.status.stringValue=e.localizedDescription}}
        }
    }
    func present(_ image:CGImage){original=image;if canvas.preview{renderPreview()}else{canvas.image=image;showPhotograph()}}
    /// Decodes the photograph the user is heading for, so the next step shows it at once. Only the photograph on
    /// screen and its two neighbours are kept; each is about 30 MB.
    func readAhead(from i:Int){
        let near=[i-1,i,i+1].filter{project.pages.indices.contains($0)}.map{project.pages[$0].path}
        decoded=decoded.filter{near.contains($0.key)}
        let next=i+travel;guard project.pages.indices.contains(next) else{return}
        let path=project.pages[next].path;guard decoded[path]==nil else{return}
        displayQueue.addOperation{[weak self] in
            guard let image=try? Imaging.load(URL(fileURLWithPath:path),maxPixel:3200) else{return}
            DispatchQueue.main.async{guard let self,let now=self.current,[now-1,now,now+1].contains(where:{self.project.pages.indices.contains($0) && self.project.pages[$0].path==path}) else{return};self.decoded[path]=image}
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
        showSmudgeState()
        canvas.zones=current.flatMap{project.pages[$0].pictureZones} ?? []
        if !canvas.isDraggingSplit {canvas.split=current.flatMap{project.pages[$0].split}};canvas.rotation=current.map{project.pages[$0].rotation} ?? 0
        guard let i=current else{
            detail.stringValue="Import photographs to begin";note.isHidden=true;candidates.removeAllItems();counter.stringValue="";window?.subtitle="";resolutionLabel.stringValue="";return
        }
        let p=project.pages[i]
        let tilt=p.deskew.map{" · deskew "+$0.map{String(format:"%.1f°",$0)}.joined(separator:" / ")} ?? ""
        deskewHalfRow?.isHidden=Exporter.previewParts(p) != 2
        detail.stringValue="\(URL(fileURLWithPath:p.path).lastPathComponent)\n\(p.reviewed ? "Reviewed":p.status) · rotation \(p.rotation*90)°\(tilt)"
        let waiting=ReviewProgress.state(p.id,active:reviewActive,pending:reviewPending)
        note.stringValue=waiting?.label ?? p.reviewNote ?? "";note.isHidden=note.stringValue.isEmpty
        note.textColor=waiting == nil ? .labelColor:.secondaryLabelColor
        candidates.removeAllItems();candidates.addItem(withTitle:p.candidates.isEmpty ? "No proposals":"Choose proposal")
        for (j,c) in p.candidates.enumerated(){candidates.addItem(withTitle:"\(j+1) · \(c.source)")}
        if let selected=p.candidates.firstIndex(where:{$0.quad==p.quad}){candidates.selectItem(at:selected+1)}
        counter.stringValue="Photo \(i+1) of \(project.pages.count) · \(reviewed) reviewed";window?.subtitle=saveFailure ?? counter.stringValue
        let a=p.adjustments ?? Adjustments()
        cleanupControl.selectedSegment=Cleanup.allCases.firstIndex(of:a.cleanup) ?? 0;cleanupName.stringValue=a.cleanup.title
        brightnessSlider.doubleValue=a.brightness;contrastSlider.doubleValue=a.contrast;sharpnessSlider.doubleValue=a.sharpness ?? 0;exposureSlider.doubleValue=a.exposure ?? 0;showAdjustmentValues()
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
    /// False for a session that was never given a name; its file in Application Support is a recovery copy.
    var hasProjectFile: Bool {supportURL.map{!LaunchPolicy.isUntitled(projectURL,in:$0)} ?? !LaunchPolicy.isUntitled(projectURL)}
    func updateTitle(){
        let name=projectURL.deletingPathExtension().lastPathComponent,untitled = !hasProjectFile
        window?.title=untitled ? "Untitled":name;window?.representedURL=untitled ? nil:projectURL;window?.isDocumentEdited=unsaved
        let path=untitled ? nil:projectURL.path;updateJournal{$0.project=path}
    }
    func noteRecent(){if testDirectory == nil,notedRecent != projectURL {notedRecent=projectURL;NSDocumentController.shared.noteNewRecentDocumentURL(projectURL)}}
    /// Records that the project changed. An untitled session is written at once; a project file waits for Save
    /// or the auto-save timer. `change` is false when only the page on screen moved.
    func save(change:Bool=true){
        if change {deviationCache=nil}
        if hasProjectFile {
            if change {
                unsaved=true
                // A copy of the unsaved state is kept aside once the edits pause, in case the app does not get to Save.
                NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(writeRecoveryCopy),object:nil)
                perform(#selector(writeRecoveryCopy),with:nil,afterDelay:2)
            }
            updateTitle();return
        }
        if change {untitledChanged=true}
        // Writing a long project takes tens of milliseconds, so a run of steps or edits is written once it pauses.
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(writeUntitled),object:nil)
        perform(#selector(writeUntitled),with:nil,afterDelay:1)
    }
    /// Writes an untitled session's file now. False when it could not be written.
    @objc @discardableResult func writeUntitled()->Bool {
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(writeUntitled),object:nil)
        return hasProjectFile ? true:write()
    }
    /// Before the project on screen is replaced by another: untitled work must be safely in its file, or the user
    /// must have said it can go. Its file is the only copy there is.
    func readyToReplace()->Bool {
        commitAdjustments()
        guard !hasProjectFile,!project.pages.isEmpty,!writeUntitled(),testDirectory == nil else{return true}
        let alert=NSAlert();alert.alertStyle = .warning;alert.messageText="This untitled work could not be kept"
        alert.informativeText="\(saveFailure ?? "Its file could not be written.")\n\nIf you carry on, the work on screen is lost. Cancel to stay with it and save it somewhere else with File ▸ Save Project As."
        alert.addButton(withTitle:"Cancel");alert.addButton(withTitle:"Discard It")
        return alert.runModal() == .alertSecondButtonReturn
    }
    @discardableResult func write()->Bool {
        commitAdjustments()
        // An untitled project nothing was added to leaves no file behind.
        guard LaunchPolicy.shouldWrite(pageCount:project.pages.count,fileExists:FileManager.default.fileExists(atPath:projectURL.path)) else{unsaved=false;updateTitle();return true}
        do{try project.save(projectURL);unsaved=false;saveFailure=nil;dropRecoveryCopy();updateTitle();refreshDetail();noteRecent();return true}
        catch{saveFailure="SAVE FAILED — \(error.localizedDescription)";window?.subtitle=saveFailure!;status.stringValue="SAVE FAILED: \(error.localizedDescription)";return false}
    }
    // MARK: Recovery
    /// Writes this session's recovery copy: the named project as it stands, unsaved changes included.
    @objc func writeRecoveryCopy(){
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(writeRecoveryCopy),object:nil)
        guard hasProjectFile,unsaved,!project.pages.isEmpty else{return}
        do{try RecoverySnapshot(id:sessionID,originalPath:projectURL.path,written:Date(),project:project).write(in:supportURL)}
        catch{status.stringValue="Could not write the recovery copy: \(error.localizedDescription)"}
    }
    /// The copy is no longer needed: its changes are in the project file, or were knowingly discarded.
    func dropRecoveryCopy(){
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(writeRecoveryCopy),object:nil)
        RecoverySnapshot.remove(sessionID,in:supportURL)
    }
    func recoveryEntries()->[RecoveryList.Entry] {
        let modified={(path:String) in (try? FileManager.default.attributesOfItem(atPath:path))?[.modificationDate] as? Date}
        let own=hasProjectFile ? nil:projectURL
        // Copies that cannot be read are listed too, so that they are known about and can be removed.
        return RecoveryList.entries(in:supportURL,except:sessionID,exceptFile:own,exists:FileManager.default.fileExists(atPath:),modified:modified)+RecoveryList.damaged(in:supportURL,exceptFile:own,modified:modified)
    }
    @objc func showRecovery(){
        if recovery == nil {
            recovery=RecoveryController()
            recovery!.entries={[weak self] in self?.recoveryEntries() ?? []}
            recovery!.onOpen={[weak self] entry,saveAs in self?.recover(entry,saveAs:saveAs)}
        }
        recovery!.show()
    }
    /// Opens a recovery copy. A named project's copy opens as that project with its changes unsaved, so the file
    /// itself changes only when the user saves; `saveAs` asks for a new file at once.
    func recover(_ entry:RecoveryList.Entry,saveAs:Bool){
        if entry.reason == .damaged {
            let alert=NSAlert();alert.alertStyle = .warning;alert.messageText="This copy is damaged and cannot be opened"
            alert.informativeText="Its file is at:\n\(entry.file.path)\n\nIt is kept until you delete it here, in case it can be repaired by hand."+(entry.originalPath.map{"\n\nThe project it belongs to, as last saved, is at:\n\($0)"} ?? "")
            if testDirectory == nil {alert.runModal()};return
        }
        guard confirmUnsaved() else{return}
        if entry.snapshot == nil {open(entry.file)} else {
            do {
                let copy=try RecoverySnapshot.read(entry.file)
                guard let original=copy.originalPath else{throw CropError.message("This recovery copy does not say which project it belongs to")}
                guard readyToReplace() else{return}
                show(copy.project,at:URL(fileURLWithPath:original))
                // The copy stays this session's own until the project is saved.
                sessionID=copy.id;unsaved=true;updateTitle()
                status.stringValue="Recovered unsaved changes to \(projectURL.lastPathComponent) · Save writes them to the project"
            } catch {showError(error);return}
        }
        recovery?.reload()
        if saveAs {self.saveAs(nil);recovery?.reload()}
    }
    /// At launch, says so when a project's unsaved changes were left behind by a crash.
    func offerRecovery(){
        guard testDirectory == nil,recoveryEntries().contains(where:{$0.reason.needsAttention}) else{return}
        showRecovery();recovery?.note.stringValue="KettleStitch closed before these changes were saved. Open a copy to carry on from where you were."
    }
    @objc func saveProject(){
        guard hasProjectFile else{saveAs();return}
        if write() {status.stringValue="Saved \(projectURL.lastPathComponent)"}
    }
    /// Asks what to do with unsaved changes before the project is closed or replaced. False means stay.
    /// `leaving` is true when the app is quitting or its window closing. Work that was never given a file is then
    /// asked about too; replacing it by opening something else is not, since it stays under Open Recent.
    func confirmUnsaved(leaving:Bool=false)->Bool {
        // A slider change still waiting to be recorded counts as a change.
        commitAdjustments()
        let action=LaunchPolicy.onQuit(hasProjectFile:hasProjectFile,unsaved:unsaved,untitledChanged:untitledChanged,pageCount:project.pages.count,autosave:UserDefaults.standard.bool(forKey:SettingsController.autosaveKey))
        // A test run has nobody to answer.
        if testDirectory != nil {return action == .nothing || action == .askToName ? true:write()}
        switch action {
        case .nothing:return true
        case .saveQuietly:return write()
        case .askToSave:break
        case .askToName:
            guard leaving else{return true}
            let kept=writeUntitled()
            let alert=NSAlert();alert.messageText="Do you want to save this project?"
            alert.informativeText=kept ? "It has not been saved to a file yet. If you don’t save it, it is kept as an untitled session that you can find again under File ▸ Recovery or Open Recent.":"It has not been saved to a file yet, and it could not be kept as an untitled session (\(saveFailure ?? "its file could not be written")). If you don’t save it, it will be lost."
            alert.addButton(withTitle:"Save…");alert.addButton(withTitle:"Cancel");alert.addButton(withTitle:"Don’t Save")
            switch alert.runModal() {
            case .alertFirstButtonReturn:return saveAs(nil)
            case .alertSecondButtonReturn:return false
            default:untitledChanged=false;return true
            }
        }
        let alert=NSAlert();alert.messageText="Do you want to save the changes made to “\(projectURL.deletingPathExtension().lastPathComponent)”?"
        alert.informativeText="Your changes will be lost if you don’t save them."
        alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel");alert.addButton(withTitle:"Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:return write()
        case .alertSecondButtonReturn:return false
        default:unsaved=false;dropRecoveryCopy();updateTitle();return true
        }
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
        save();refreshDetail();table.reloadData(forRowIndexes:IndexSet(indexes),columnIndexes:IndexSet(integer:0));if canvas.preview{renderPreview()}else{showPhotograph()}
        deviations?.refresh()
    }
    func invalidateWork(){queue.cancelAllOperations();splitQueue.cancelAllOperations();generation=UUID();detecting=false;endProgress(.detect);endProgress(.split)}
    func restructure(_ change:()->Void){
        undoStack.append(.structure(project.pages,project.selected));redoStack.removeAll();invalidateWork();change()
        project.selected=min(max(0,project.selected),max(0,project.pages.count-1));save();writeUntitled();reloadPages();selectCurrent()
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
    // Restoring an import brings back photographs whose detection was cancelled; it starts again.
    @objc func undo(){if let text=editedText{text.undoManager?.undo();return};if adjusting{commitAdjustments()};guard let entry=undoStack.popLast() else{return};if let inverse=exchange(entry){redoStack.append(inverse)};save();reloadPages();selectCurrent();if case .structure=entry{detectPending()}}
    @objc func redo(){if let text=editedText{text.undoManager?.redo();return};if adjusting{commitAdjustments()};guard let entry=redoStack.popLast() else{return};if let inverse=exchange(entry){undoStack.append(inverse)};save();reloadPages();selectCurrent();if case .structure=entry{detectPending()}}

    // MARK: Navigation and crop actions
    func navigate(_ d:Int){
        guard let i=current else{return};let target=min(project.pages.count-1,max(0,i+d))
        // Nothing further that way: the photograph stays as it is and the canvas says so.
        guard target != i else{canvas.flashEdges();return}
        travel=target>i ? 1:-1;project.selected=target;selectCurrent();save(change:false)
    }
    func show(_ index:Int){guard project.pages.indices.contains(index) else{return};project.selected=index;selectCurrent();save(change:false)}
    @objc func previous(){navigate(-1)}
    @objc func next(){navigate(1)}
    @objc func firstPage(){show(0)}
    @objc func lastPage(){show(project.pages.count-1)}
    @objc func accept(){edit{$0.reviewed=true};navigate(1)}
    func nextMatching(_ test:(Page)->Bool){guard let i=current else{return};for d in 1...project.pages.count {let j=(i+d)%project.pages.count;if test(project.pages[j]){show(j);return}};NSSound.beep()}
    @objc func nextReview(){nextMatching{!$0.reviewed}}
    @objc func nextFlagged(){nextMatching{$0.flagged==true}}
    @objc func selectAllPages(){table.selectAll(nil);status.stringValue="\(table.selectedRowIndexes.count) pages selected — settings, flags, export and Send to \(ReviewChoice.provider.name) apply to all of them"}
    @objc func toggleFlag(){guard let i=current else{return};let on=project.pages[i].flagged != true;edit(targetIndexes,geometry:false){$0.flagged=on ? true:nil}}
    @objc func fit(){canvas.fit()}
    @objc func zoomIn(){canvas.zoom=min(8,canvas.zoom*1.25)}
    @objc func zoomOut(){canvas.zoom=max(0.5,canvas.zoom/1.25)}
    @objc func zoomSegment(_ sender:NSToolbarItemGroup){[zoomOut,fit,zoomIn][sender.selectedIndex]()}
    /// Turns every selected page a quarter turn. One Undo turns them all back.
    func turn(_ quarter:Int){
        let targets=targetIndexes
        turnPages(targets){_ in quarter}
        if targets.count>1 {status.stringValue="Turned \(targets.count) pages"}
    }
    /// Turns each page by the number of quarter turns `quarters` gives for it, as one change.
    func turnPages(_ indexes:[Int],_ quarters:(Page)->Int){
        let changing=indexes.filter{((quarters(project.pages[$0])%4)+4)%4 != 0};guard !changing.isEmpty else{return}
        // A split is measured across the output, so a quarter turn leaves nothing to keep: propose it afresh.
        let split=changing.filter{project.pages[$0].split != nil}
        edit(changing){let by=quarters($0);$0.rotation=((($0.rotation+by)%4)+4)%4;$0.split=$0.split?.rotated(quarterTurns:by);if $0.split == nil {$0.splitByHand=nil}
            // The tilt of one page turns with it; the two pages of a spread change places, or stop being the pages measured.
            $0.deskew=Page.deskew(Page.deskew($0.deskew,afterQuarterTurns:by,parts:$0.deskew?.count ?? 1),fitting:$0.split == nil ? 1:2)}
        let lost=split.filter{project.pages[$0].split == nil}
        if !lost.isEmpty {proposeSplits(lost,record:false)}
        // The photograph is shown turned as well as the preview, so the view stays as it was.
    }
    /// Rotation is copied and pasted on its own, apart from the image settings and page format.
    @objc func copyRotation(){
        guard let i=current else{return};copiedRotation=project.pages[i].rotation
        status.stringValue="Copied this page's rotation (\(project.pages[i].rotation*90)°)"
    }
    @objc func pasteRotation(){
        guard let rotation=copiedRotation else{return};let targets=targetIndexes
        let changed=targets.filter{project.pages[$0].rotation != rotation}.count
        turnPages(targets){rotation-$0.rotation}
        status.stringValue=changed==0 ? "Already turned that way":"Pasted rotation (\(rotation*90)°) to \(changed) page\(changed==1 ? "":"s")"
    }

    // MARK: Page split
    /// The first press looks for the fold. Pressing again on the same page, with the split still where it was put,
    /// steps through the detector's other candidates and round to the first.
    @objc func proposeSplit(){
        let targets=targetIndexes
        if targets.count==1,let i=targets.first,let kept=splitOptions[project.pages[i].id],kept.options.count>1,kept.quad==project.pages[i].quad,kept.rotation==project.pages[i].rotation,project.pages[i].split==kept.options[kept.index] {
            let next=(kept.index+1)%kept.options.count
            splitOptions[project.pages[i].id]?.index=next
            edit([i],geometry:false){$0.split=kept.options[next];$0.splitByHand=true}
            status.stringValue=next==0 ? "Back to the first split proposal (1 of \(kept.options.count)) · t for the next":"Split candidate \(next+1) of \(kept.options.count) · t for the next"
            return
        }
        proposeSplits(targets,record:true)
    }
    /// Proposes a split on every page that has none, working down the book so each goes by the one before.
    /// Pages already split are left alone, since those may have been put right by hand. Never done unasked.
    @objc func proposeAllSplits(){
        let unsplit=project.pages.indices.filter{project.pages[$0].split == nil}
        guard !unsplit.isEmpty else{status.stringValue=project.pages.isEmpty ? "There are no pages to split":"Every page already has a split";return}
        proposeSplits(unsplit,record:true)
    }
    /// Looks for the fold on each page in the background. One undo step covers the whole request.
    func proposeSplits(_ indexes:[Int],record:Bool){
        guard !indexes.isEmpty else{return}
        let pages=indexes.map{project.pages[$0]},token=generation
        if record {undoStack.append(.pages(pages));redoStack.removeAll()}
        status.stringValue=pages.count==1 ? "Looking for the fold…":"Looking for the fold on \(pages.count) pages…"
        if pages.count>1 {beginProgress(.split,pages.count)}
        var found=0,finished=0,guided=0,failed=0,stale=0,trouble=""
        for page in pages {
            splitQueue.addOperation{[weak self] in
                // Read when this page's turn comes, so each page of a batch goes by the one just done before it.
                // The page before is trusted when the user has placed or accepted its split, or is working through
                // the book one page at a time and so has just seen it. In a batch, a split nobody has looked at is only a hint.
                let (guide,trusted)=DispatchQueue.main.sync{()->(PageSplit?,Bool) in
                    guard let self,self.generation==token,let i=self.project.pages.firstIndex(where:{$0.id==page.id}),let before=SplitDetector.guidePage(for:i,in:self.project.pages) else{return (nil,false)}
                    let earlier=self.project.pages[before]
                    return (earlier.split,pages.count==1 || earlier.splitByHand==true || earlier.reviewed)
                }
                let result:Result<SplitProposal,Error>=autoreleasepool{Result{try SplitDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),quad:page.quad,rotation:page.rotation,guide:guide,trusted:trusted)}}
                DispatchQueue.main.async{guard let self,self.generation==token else{return}
                    finished+=1
                    // The crop, the turn or the split itself may have changed while this ran, by hand or by Undo; a
                    // proposal for the page as it was is not laid over what the user has done since.
                    if case .failure(let error)=result {failed+=1;trouble=error.localizedDescription}
                    else if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),page.splitResultApplies(to:self.project.pages[i]),case .success(let proposal)=result {
                        self.project.pages[i].split=proposal.split;self.project.pages[i].splitByHand=nil;if trusted,guide != nil{guided+=1}else if proposal.confident{found+=1}else if guide != nil{guided+=1}
                        self.project.pages[i].deskew=Page.deskew(self.project.pages[i].deskew,fitting:2)
                        self.splitOptions[page.id]=(proposal.alternatives,0,page.quad,page.rotation)
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.refreshDetail();if self.canvas.preview {self.renderPreview()}}
                    } else {stale+=1}
                    self.stepProgress(.split,finished)
                    if finished==pages.count {
                        self.endProgress(.split)
                        if pages.count==1,failed+stale==1 {self.status.stringValue=failed==1 ? "Could not look for the fold: \(trouble)":"The page changed while the fold was looked for; nothing was applied"} else {self.status.stringValue=pages.count==1 ? (found==1 ? "Split proposed at the fold — t again tries another place; drag it, or press y and u to move it":guided==1 ? "Split placed by the page before, adjusted to this page — t again tries another place; drag it, or press y and u to move it":"No clear fold found; split placed at the centre — drag it, or press y and u to move it"):"Split proposed on \(pages.count) pages: \(found) at a fold, \(guided) where the page before has it, \(pages.count-failed-stale-found-guided) at the centre";if failed+stale>0 {self.status.stringValue+=(failed>0 ? " · \(failed) could not be read (\(trouble))":"")+(stale>0 ? " · \(stale) changed meanwhile and \(stale==1 ? "was":"were") left alone":"")}}
                    }
                }
            }
        }
    }
    // MARK: Deskew, picture zones and deviations
    @objc func deskew(){
        let targets=targetIndexes;guard !targets.isEmpty else{return}
        let pages=targets.map{project.pages[$0]},token=generation
        // One half of a spread is measured alone only for the page on screen; a selection of pages is done whole.
        let only=targets.count==1 && targets[0]==current ? deskewPart:nil
        undoStack.append(.pages(pages));redoStack.removeAll()
        status.stringValue=pages.count==1 ? "Measuring the tilt of the text…":"Measuring the tilt on \(pages.count) pages…"
        if pages.count>1 {beginProgress(.split,pages.count)}
        var found=0,finished=0,failed=0,stale=0,trouble=""
        for page in pages {
            splitQueue.addOperation{[weak self] in
                let result:Result<[Double]?,Error>=autoreleasepool{Result{try SkewDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),page:page)}}
                DispatchQueue.main.async{guard let self,self.generation==token else{return}
                    finished+=1
                    // Measured on the page as it was; a crop, turn, split or deskew changed since, by hand or by
                    // Undo, would not match. A measurement that found no clear tilt leaves the page as it is.
                    if case .failure(let error)=result {failed+=1;trouble=error.localizedDescription}
                    else if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),page.deskewResultApplies(to:self.project.pages[i]),case .success(let angles)=result {
                        if let angles {
                            found+=1
                            self.project.pages[i].deskew=Page.deskew(self.project.pages[i].deskew,setting:angles,parts:Exporter.previewParts(page),only:only)
                            self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
                            if self.current==i {self.refreshDetail();if self.canvas.preview{self.renderPreview()}else{self.setPreview(true)}}
                        }
                    } else {stale+=1}
                    if pages.count>1 {self.stepProgress(.split,finished)}
                    if finished==pages.count {
                        if pages.count>1 {self.endProgress(.split)}
                        let unclear=pages.count-found-failed-stale
                        let notes=(failed>0 ? " · \(failed) could not be read (\(trouble))":"")+(stale>0 ? " · \(stale) changed meanwhile and \(stale==1 ? "was":"were") left alone":"")
                        self.status.stringValue=pages.count==1 ? (found==1 ? "Deskewed — Option-, and Option-. turn it by 0.1°":failed==1 ? "Could not measure the tilt: \(trouble)":stale==1 ? "The page changed while its tilt was measured; nothing was applied":"No clear tilt found; the page is left as it is"):"Deskewed \(found) of \(pages.count) pages; \(unclear) showed no clear tilt"+notes
                    }
                }
            }
        }
    }
    @objc func removeDeskew(){
        let targets=targetIndexes.filter{project.pages[$0].deskew != nil};guard !targets.isEmpty else{return}
        if targets.count==1,targets[0]==current,let only=deskewPart {
            edit(geometry:false){$0.deskew=Page.deskew($0.deskew,setting:nil,parts:2,only:only)};status.stringValue="Deskew removed from \(AppDelegate.halfNames[only+1])";return
        }
        edit(targets,geometry:false){$0.deskew=nil};status.stringValue="Deskew removed"
    }
    func turnDeskew(_ delta:Double){
        guard let i=current else{return}
        let turned=Page.nudged(project.pages[i].deskew,by:delta,parts:Exporter.previewParts(project.pages[i]),only:deskewPart)
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
    // MARK: Smudge brush
    @objc func toggleSmudge(){setSmudging(!canvas.smudgeMode);showSmudgeState()}
    func setSmudging(_ on:Bool){
        guard on != canvas.smudgeMode else{return}
        if on {
            guard current != nil,original != nil else{return}
            if canvas.preview{setPreview(false)}
            canvas.zoneMode=false;canvas.cloneMode=false;canvas.smudgeRadius=smudgeSizeSlider.doubleValue;window.makeFirstResponder(canvas)
            status.stringValue="Smudge brush: drag over the print to blur it · Brush, Strength and Grain are in the inspector · Escape puts the brush down"
        } else {status.stringValue="Smudge brush put down"}
        canvas.smudgeMode=on;showSmudgeState()
    }
    @objc func removeSmudges(){
        let targets=targetIndexes.filter{project.pages[$0].smudges != nil};guard !targets.isEmpty else{status.stringValue="No smudges to remove";return}
        edit(targets,geometry:false){$0.smudges=nil};status.stringValue="Smudges removed"
    }
    // MARK: Clone brush
    @objc func toggleClone(){setCloning(!canvas.cloneMode);showSmudgeState()}
    func setCloning(_ on:Bool){
        guard on != canvas.cloneMode else{return}
        if on {
            guard current != nil,original != nil else{return}
            if canvas.preview{setPreview(false)}
            canvas.zoneMode=false;canvas.smudgeMode=false;canvas.smudgeRadius=smudgeSizeSlider.doubleValue;window.makeFirstResponder(canvas)
            status.stringValue="Clone brush: Option-click the place to copy from, then drag where the copy should go · Escape puts the brush down"
        } else {status.stringValue="Clone brush put down"}
        canvas.cloneMode=on;showSmudgeState()
    }
    @objc func removeClones(){
        let targets=targetIndexes.filter{project.pages[$0].clones != nil};guard !targets.isEmpty else{status.stringValue="Nothing cloned to remove";return}
        edit(targets,geometry:false){$0.clones=nil};status.stringValue="Cloned areas removed"
    }
    /// A brush's button is lit while that brush is in hand, when its settings show: width for either brush, strength
    /// and grain for the smudge alone. A crossed-out button works only when a page it would act on has something to remove.
    func showSmudgeState(){
        smudgeButton.state=canvas.smudgeMode ? .on:.off;cloneButton.state=canvas.cloneMode ? .on:.off
        brushRow?.isHidden = !(canvas.smudgeMode || canvas.cloneMode)
        for row in smudgeRows {row.isHidden = !canvas.smudgeMode}
        clearSmudgeButton.isEnabled=targetIndexes.contains{project.pages[$0].smudges != nil}
        clearCloneButton.isEnabled=targetIndexes.contains{project.pages[$0].clones != nil}
    }
    @objc func smudgeBrushChanged(_ sender:Any?){
        canvas.smudgeRadius=smudgeSizeSlider.doubleValue
        smudgeSizeValue.stringValue=String(Int((smudgeSizeSlider.doubleValue/smudgeSizeSlider.maxValue*100).rounded()));smudgeStrengthValue.stringValue=String(Int((smudgeStrengthSlider.doubleValue*100).rounded()))
        smudgeGrainValue.stringValue=String(Int((smudgeGrainSlider.doubleValue*100).rounded()))
        UserDefaults.standard.set(smudgeSizeSlider.doubleValue,forKey:"smudgeSize");UserDefaults.standard.set(smudgeStrengthSlider.doubleValue,forKey:"smudgeStrength");UserDefaults.standard.set(smudgeGrainSlider.doubleValue,forKey:"smudgeGrain")
        if canvas.cloneMode {canvas.needsDisplay=true}
    }
    /// Outside preview the canvas shows the photograph with its smudges blurred in, where they were painted.
    func showPhotograph(){
        guard let image=original,let i=current,!canvas.preview else{return}
        let smudges=project.pages[i].smudges ?? [],clones=project.pages[i].clones ?? []
        guard !smudges.isEmpty || !clones.isEmpty else{if canvas.image !== image {displayToken=UUID();canvas.image=image};return}
        let token=UUID();displayToken=token
        displayQueue.cancelAllOperations()
        displayQueue.addOperation{[weak self] in let result=try? Imaging.retouched(image,smudges:smudges,clones:clones)
            DispatchQueue.main.async{guard let self,self.displayToken==token,!self.canvas.preview,let result else{return};self.canvas.image=result}
        }
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
        edit(targets,geometry:false){$0.split=nil;$0.splitByHand=nil;$0.deskew=Page.deskew($0.deskew,fitting:1)};status.stringValue=targets.count==1 ? "Split removed; this photograph exports as one page":"Split removed from \(targets.count) pages"
    }
    func moveSplit(_ delta:Double){
        guard let i=current,let split=project.pages[i].split else{NSSound.beep();return}
        let moved=split.moved(by:delta);if moved != split {edit(geometry:false){$0.split=moved;$0.splitByHand=true}}
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
        // h j k l are the left, bottom, top and right as seen, whichever way the page is turned.
        let turn=ViewTurn(project.pages[i].rotation),edge=turn.storedEdge(seenAt:["h":3,"j":2,"k":0,"l":1][key]!)
        let step=0.005*(inward ? -1.0:1.0)
        let delta=turn.photographDelta(Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0))
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
        let changed=canvas.preview != on
        canvas.preview=on;previewItem?.setSelected(on,at:0)
        if changed {table.reloadData(forRowIndexes:IndexSet(integersIn:0..<project.pages.count),columnIndexes:IndexSet(integer:0))}
        if on{canvas.smudgeMode=false;canvas.cloneMode=false;showSmudgeState();renderPreview()}else if original != nil{displayToken=UUID();canvas.image=original;canvas.fit();showPhotograph()}
    }
    @objc func togglePreview(){setPreview(!canvas.preview)}
    func renderPreview(){guard let image=original,let i=current else{return};let p=project.pages[i],token=UUID();displayToken=token
        displayQueue.cancelAllOperations()
        displayQueue.addOperation{[weak self] in let result=Result{try Exporter.preview(image,page:p)};DispatchQueue.main.async {guard let self,self.displayToken==token,self.canvas.preview else{return};switch result{
            case .success(let output):
                // Keep zoom and pan while only the tones change.
                let resized=self.canvas.image?.width != output.width || self.canvas.image?.height != output.height
                self.canvas.showOutput(output);if resized{self.canvas.fit()}
            case .failure(let e):self.showError(e)}}}
    }
    @objc func candidateChanged(){guard let i=current else{return};let j=candidates.indexOfSelectedItem-1;guard project.pages[i].candidates.indices.contains(j) else{return};let q=project.pages[i].candidates[j].quad;edit{$0.selectProposal(q)}}
    func cycleCandidate(_ delta:Int){guard candidates.numberOfItems>1 else{return};let count=candidates.numberOfItems-1;let current=candidates.indexOfSelectedItem-1;let index=(current<0 ? (delta>0 ? 0:count-1):(current+delta+count)%count)+1;candidates.selectItem(at:index);candidateChanged();candidates.selectItem(at:index)}
    @objc func previousCandidate(){cycleCandidate(-1)}
    @objc func nextCandidate(){cycleCandidate(1)}

    // MARK: Image settings and page format
    @objc func adjustmentChanged(_ sender:Any?){
        var a=Adjustments();a.cleanup=Cleanup.allCases[max(0,cleanupControl.selectedSegment)];a.brightness=brightnessSlider.doubleValue;a.contrast=contrastSlider.doubleValue
        // Whole steps of the number shown, so the middle of a slider is exactly neutral.
        a.brightness=(a.brightness*100).rounded()/100;a.contrast=(a.contrast*100).rounded()/100
        let sharpness=(sharpnessSlider.doubleValue*100).rounded()/100;a.sharpness=sharpness>0 ? sharpness:nil
        let exposure=(exposureSlider.doubleValue*100).rounded()/100;a.exposure=exposure != 0 ? exposure:nil
        showAdjustmentValues()
        // Specks only exist once the page is black and white.
        a.despeckle=a.cleanup == .blackAndWhite && despeckleControl.selectedSegment>0 ? despeckleControl.selectedSegment:nil;despeckleControl.isEnabled=a.cleanup == .blackAndWhite
        setAdjustments(a)
    }
    /// Gives this page the cleanup, despeckle, brightness, contrast and sharpness of the page before it.
    /// The preview comes on first, so the page is seen as it was and then as it becomes.
    @objc func copyPreviousAdjustments(){
        guard let i=current,i>0 else{NSSound.beep();status.stringValue="There is no page before this one to copy adjustments from";return}
        let adjustments=project.pages[i-1].adjustments
        if !canvas.preview {setPreview(true)}
        guard project.pages[i].adjustments != adjustments else{status.stringValue="This page already has the previous page's image settings";return}
        edit([i],geometry:false){$0.adjustments=adjustments}
        status.stringValue=adjustments == nil ? "The previous page has no image settings; this page's were removed":"Copied the previous page's image settings (\((adjustments ?? Adjustments()).cleanup.title) cleanup, exposure, brightness, contrast, sharpness)"
    }
    // MARK: Presets
    func keepPresets(_ list:[SettingsPreset]){
        presets=list;if testDirectory == nil,let data=try? PresetStore.encode(list) {UserDefaults.standard.set(data,forKey:PresetStore.key)}
        presetUses=presetUses.filter{name,_ in list.contains{$0.name==name}}
        if testDirectory == nil {UserDefaults.standard.set(presetUses,forKey:PresetStore.usesKey)}
        rebuildPresetMenu(presetPopup.menu!,title:true);rebuildToolsPresetMenu()
    }
    /// The presets by name, the three applied most often carrying ⌘1, ⌘2 and ⌘3.
    func rebuildToolsPresetMenu(){
        toolsPresetMenu.removeAllItems()
        let numbered=PresetStore.mostUsed(presets,uses:presetUses)
        for preset in presets {
            let number=numbered.firstIndex(of:preset.name).map{String($0+1)} ?? ""
            let item=toolsPresetMenu.addItem(withTitle:preset.name,action:#selector(applyPresetItem(_:)),keyEquivalent:number);item.keyEquivalentModifierMask=[.command]
            item.target=self;item.representedObject=preset.name;item.toolTip=preset.summary
        }
        if presets.isEmpty {toolsPresetMenu.addItem(withTitle:"No presets yet — save one from Image Settings",action:nil,keyEquivalent:"")}
    }
    /// Fills a menu with the presets, then the commands to keep the current settings as one and to delete one.
    func rebuildPresetMenu(_ menu:NSMenu,title:Bool){
        menu.removeAllItems()
        if title {menu.addItem(withTitle:presets.isEmpty ? "No presets yet":"Apply a preset",action:nil,keyEquivalent:"")}
        for preset in presets {
            let item=menu.addItem(withTitle:preset.name,action:#selector(applyPresetItem(_:)),keyEquivalent:"");item.target=self;item.representedObject=preset.name;item.toolTip=preset.summary
        }
        if !presets.isEmpty {menu.addItem(.separator())}
        menu.addItem(withTitle:"Save These Settings as a Preset…",action:#selector(savePresetAsked),keyEquivalent:"").target=self
        if !presets.isEmpty {
            let delete=NSMenu()
            for preset in presets {let item=delete.addItem(withTitle:preset.name,action:#selector(deletePresetItem(_:)),keyEquivalent:"");item.target=self;item.representedObject=preset.name}
            menu.addItem(withTitle:"Delete Preset",action:nil,keyEquivalent:"").submenu=delete
        }
    }
    @objc func applyPresetItem(_ sender:NSMenuItem){if let name=sender.representedObject as? String {applyPreset(named:name)}}
    @objc func deletePresetItem(_ sender:NSMenuItem){
        guard let name=sender.representedObject as? String else{return}
        keepPresets(PresetStore.removing(name,from:presets));status.stringValue="Deleted the preset “\(name)” · pages it was applied to keep their settings"
    }
    /// Gives the selected pages a preset's image settings, and its page format if it has one, as one change.
    func applyPreset(named name:String){
        guard let preset=presets.first(where:{$0.name==name}) else{return}
        let targets=targetIndexes;guard !targets.isEmpty else{NSSound.beep();return}
        if !canvas.preview {setPreview(true)}
        edit(targets,geometry:false){preset.apply(to:&$0)}
        presetUses=PresetStore.counting(preset.name,in:presetUses)
        if testDirectory == nil {UserDefaults.standard.set(presetUses,forKey:PresetStore.usesKey)}
        rebuildToolsPresetMenu()
        status.stringValue="Applied “\(preset.name)” to \(targets.count==1 ? "this page":"\(targets.count) pages") · \(preset.summary)"
    }
    /// Keeps the page on screen's image settings under a name, with its page format if asked.
    @discardableResult func savePreset(named name:String,includeFormat:Bool)->Bool {
        guard let i=current,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return false}
        let preset=SettingsPreset(name:name,adjustments:project.pages[i].adjustments ?? Adjustments(),format:includeFormat ? (project.pages[i].format ?? PageFormat()):nil)
        keepPresets(PresetStore.adding(preset,to:presets));status.stringValue="Saved the preset “\(name.trimmingCharacters(in:.whitespacesAndNewlines))” · \(preset.summary)"
        return true
    }
    @objc func savePresetAsked(){
        guard current != nil else{NSSound.beep();return}
        let alert=NSAlert();alert.messageText="Save these image settings as a preset";alert.informativeText="The preset keeps this page's mode, exposure, brightness, contrast, sharpness and despeckle. Choose it later from the Preset menu to give them to the selected pages."
        let name=NSTextField(frame:NSRect(x:0,y:28,width:280,height:24));name.placeholderString="Name, such as Text pages"
        let format=NSButton(checkboxWithTitle:"Also keep this page's format (width or paper size)",target:nil,action:nil);format.frame=NSRect(x:0,y:0,width:280,height:20)
        let box=NSView(frame:NSRect(x:0,y:0,width:280,height:54));box.addSubview(name);box.addSubview(format);alert.accessoryView=box
        alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel");alert.window.initialFirstResponder=name
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        let chosen=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !chosen.isEmpty else{NSSound.beep();status.stringValue="A preset needs a name";return}
        if PresetStore.isTaken(chosen,in:presets) {
            let replace=NSAlert();replace.messageText="Replace the preset “\(chosen)”?";replace.informativeText="A preset with this name already exists.";replace.addButton(withTitle:"Replace");replace.addButton(withTitle:"Cancel")
            guard replace.runModal() == .alertFirstButtonReturn else{return}
        }
        savePreset(named:chosen,includeFormat:format.state == .on)
    }
    @objc func resetAdjustments(){guard current != nil else{return};cleanupControl.selectedSegment=0;brightnessSlider.doubleValue=0;contrastSlider.doubleValue=0;sharpnessSlider.doubleValue=0;exposureSlider.doubleValue=0;showAdjustmentValues();despeckleControl.selectedSegment=0;despeckleControl.isEnabled=false;setAdjustments(Adjustments())}
    /// The number beside each slider: signed from the neutral middle for brightness and contrast, 0–100 for sharpness.
    func showAdjustmentValues(){
        func signed(_ value:Double)->String {let n=Int((value*100).rounded());return n>0 ? "+\(n)":n<0 ? "−\(-n)":"0"}
        exposureValue.stringValue=signed(exposureSlider.doubleValue);brightnessValue.stringValue=signed(brightnessSlider.doubleValue);contrastValue.stringValue=signed(contrastSlider.doubleValue)
        sharpnessValue.stringValue=String(Int((sharpnessSlider.doubleValue*100).rounded()))
    }
    /// A slider drag is one undo step: the snapshot is taken at its first change and saved once it settles.
    func setAdjustments(_ a:Adjustments){
        let targets=targetIndexes;guard !targets.isEmpty else{return}
        if !adjusting {undoStack.append(.pages(targets.map{project.pages[$0]}));redoStack.removeAll();adjusting=true}
        for i in targets {project.pages[i].adjustments=a.isIdentity ? nil:a;adjustedPages.insert(project.pages[i].id)}
        cleanupName.stringValue=a.cleanup.title
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(commitAdjustments),object:nil)
        perform(#selector(commitAdjustments),with:nil,afterDelay:0.2)
        if canvas.preview{renderPreview()}else{setPreview(true)}
    }
    @objc func commitAdjustments(){
        NSObject.cancelPreviousPerformRequests(withTarget:self,selector:#selector(commitAdjustments),object:nil)
        guard adjusting else{return};adjusting=false;save()
        // The rows of the pages that were changed, which need not be the ones selected now.
        let rows=IndexSet(project.pages.indices.filter{adjustedPages.contains(project.pages[$0].id)});adjustedPages=[]
        table.reloadData(forRowIndexes:rows,columnIndexes:IndexSet(integer:0))
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
    @objc func copySettings(){guard let i=current else{return};copiedSettings=(project.pages[i].adjustments,project.pages[i].format);status.stringValue="Copied image settings and page format"}
    @objc func pasteSettings(){guard let s=copiedSettings else{return};let targets=targetIndexes;edit(targets,geometry:false){$0.adjustments=s.0;$0.format=s.1};status.stringValue="Pasted settings to \(targets.count) page\(targets.count==1 ? "":"s")"}
    @objc func applySettingsToAll(){
        guard let i=current else{return};let a=project.pages[i].adjustments,f=project.pages[i].format
        // Said before the work, which on a long project takes a moment, and confirmed after it on the button itself.
        applyAllButton.title="Applying to \(project.pages.count) Pages…";applyAllButton.isEnabled=false;status.stringValue="Applying this page's adjustments and format to all \(project.pages.count) pages…";showBanner("Applying settings to \(project.pages.count) pages…")
        // A moment first, so the notice is on screen before the main thread is busy.
        let token=sessionID
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05){[weak self] in guard let self else{return}
            // Another project opened in that moment is not given this one's settings.
            guard self.sessionID==token else{self.showBanner(nil);self.applyAllButton.title="Apply Settings to All Pages";self.applyAllButton.isEnabled=self.current != nil;return}
            self.edit(Array(self.project.pages.indices),geometry:false){$0.adjustments=a;$0.format=f}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6){[weak self] in if self?.importing==false {self?.showBanner(nil)}};self.status.stringValue="Applied this page's adjustments and format to all \(self.project.pages.count) pages · Undo puts them back"
            self.applyAllButton.title="✓ Applied to All \(self.project.pages.count) Pages"
            DispatchQueue.main.asyncAfter(deadline:.now()+2.5){[weak self] in guard let self else{return};self.applyAllButton.title="Apply Settings to All Pages";self.applyAllButton.isEnabled=self.current != nil}
        }
    }

    // MARK: Projects
    @objc func newProject(){
        guard confirmUnsaved() else{return}
        let panel=NSSavePanel();panel.nameFieldStringValue="Book.kettlestitch";panel.message="Choose where to save the new project."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        guard readyToReplace() else{return}
        do{let fresh=Project();try fresh.save(url);writeUntitled();stop();dropRecoveryCopy();sessionID=UUID();deviationCache=nil;decoded=[:];project=fresh;projectURL=url;undoStack=[];redoStack=[];unsaved=false;untitledChanged=false;noteRecent();updateTitle();reloadPages();selectCurrent()}catch{showError(error)}
    }
    @objc func importImages(){
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true;panel.message="Choose photographs or a folder. Subfolders are not imported."
        guard panel.runModal() == .OK else{return}
        receive(panel.urls)
    }
    func application(_ application:NSApplication,open urls:[URL]){if window==nil {pendingOpen += urls} else {receive(urls)}}
    /// Files and folders from the Import panel, a drop on the window or a drop on the app's icon.
    /// A project file is opened; photographs are added to the project that is open.
    /// Says which imported photographs are incomplete files. They stay in the project, marked, so that copying
    /// each one again to the same place puts it right; nothing of them is cropped or exported meanwhile.
    func warnIncomplete(_ names:[String]){
        guard !names.isEmpty else{return}
        incompleteNames=names
        status.stringValue="\(names.count) imported photograph\(names.count==1 ? " is an incomplete file":"s are incomplete files") and cannot be used: \(names.prefix(3).joined(separator:", "))\(names.count>3 ? "…":"")"
        guard testDirectory == nil else{return}
        let alert=NSAlert();alert.alertStyle = .warning
        alert.messageText=names.count==1 ? "“\(names[0])” is an incomplete file":"\(names.count) of the photographs are incomplete files"
        let list=names.count==1 ? "":names.prefix(12).joined(separator:"\n")+(names.count>12 ? "\n… and \(names.count-12) more":"")+"\n\n"
        alert.informativeText=list+"\(names.count==1 ? "The file ends":"These files end") before the picture does, usually because copying or downloading was interrupted. \(names.count==1 ? "It is":"They are") marked in the sidebar and will not be cropped or exported. Copy \(names.count==1 ? "it":"them") again from where \(names.count==1 ? "it":"they") came, to the same place, and the page\(names.count==1 ? "":"s") will work."
        alert.runModal()
    }
    func receive(_ urls:[URL]){
        if let file=urls.first(where:ImportPolicy.isProject) {if confirmUnsaved(){open(file)};return}
        guard !importing else{status.stringValue="An import is already under way";return}
        // Listing folders and reading each photograph's size takes a while for a long book, so it happens off the
        // main thread with a notice over the canvas. This is separate from detection, which follows.
        importing=true;showBanner("Importing photographs…")
        // The session, not the file's address, says whether the project is still the one the import began in: Save As keeps it.
        let existing=Set(project.pages.map{$0.path}),target=sessionID
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let incoming=ImportPolicy.sort(urls,existing:existing){url in
                var directory:ObjCBool=false
                guard FileManager.default.fileExists(atPath:url.path,isDirectory:&directory),directory.boolValue else{return nil}
                return (try? FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? []
            }
            let count=incoming.photographs.count
            if count>0 {DispatchQueue.main.async{if self?.importing==true {self?.showBanner("Importing \(count) photograph\(count==1 ? "":"s")…")}}}
            let added=incoming.photographs.map{Page(path:$0.path)}
            // A file cut short while it was copied opens like any other; it is found now, before any work is done on it.
            let cutShort=incoming.photographs.filter{Imaging.incomplete($0) != nil}.map{$0.lastPathComponent}
            DispatchQueue.main.async{guard let self else{return}
                self.importing=false;self.showBanner(nil)
                // Another project was opened meanwhile; these photographs were meant for the one before.
                guard self.sessionID==target else{return}
                guard !added.isEmpty else{self.status.stringValue="Nothing new to import";return}
                let wasEmpty=self.project.pages.isEmpty
                self.restructure{self.project.pages += added;if wasEmpty{self.project.selected=0}}
                self.status.stringValue="Imported \(added.count) photograph\(added.count==1 ? "":"s") · proposing crops"
                self.detectPending()
                self.warnIncomplete(cutShort)
            }
        }
    }
    /// A notice over the canvas for work that holds everything else up; nil takes it away.
    func showBanner(_ text:String?){
        banner.isHidden=text==nil;bannerLabel.stringValue=text ?? ""
        if text == nil {bannerSpinner.stopAnimation(nil)} else {bannerSpinner.startAnimation(nil)}
    }
    @objc func openProject(){let panel=NSOpenPanel();panel.allowedContentTypes=ImportPolicy.projectExtensions.compactMap{UTType(filenameExtension:$0)}+[.json];guard confirmUnsaved(),panel.runModal() == .OK,let url=panel.url else{return};open(url)}
    @objc func openRecent(_ sender:NSMenuItem){if let url=sender.representedObject as? URL,confirmUnsaved(){open(url)}}
    func open(_ url:URL){
        // Changes to this project that a crash left unsaved are offered before the file as it was last saved.
        if testDirectory == nil,let copy=recoveryCopy(for:url) {
            let when=RecoveryController.date.string(from:copy.written)
            let alert=NSAlert();alert.messageText="“\(url.deletingPathExtension().lastPathComponent)” has unsaved changes that were kept"
            alert.informativeText="KettleStitch closed before changes made up to \(when) were saved. You can carry on from them, or open the project as it was last saved; the kept changes stay in File ▸ Recovery until you delete them or save over them."
            alert.addButton(withTitle:"Open with Those Changes");alert.addButton(withTitle:"Open as Last Saved");alert.addButton(withTitle:"Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:recover(copy,saveAs:false);return
            case .alertSecondButtonReturn:break
            default:return
            }
        }
        do{
            let loaded=try Project.read(url);guard readyToReplace() else{return};show(loaded,at:url)
            let pending=loaded.pages.filter{$0.status=="Pending" || $0.status==AppDelegate.detectionError}.count
            status.stringValue="Opened \(url.lastPathComponent)"+(pending>0 ? " · \(pending) page\(pending==1 ? " has":"s have") no crop proposal yet; Tools ▸ Detect All Pending Pages proposes \(pending==1 ? "it":"them")":"")
        }catch{showError(error)}
    }
    /// Replaces the project on screen with another. What was open has been saved or let go by now.
    func show(_ loaded:Project,at url:URL){
        do{writeUntitled();stop();dropRecoveryCopy();sessionID=UUID();saveFailure=nil;deviationCache=nil;generation=UUID();decoded=[:];project=loaded;project.selected=min(max(0,project.selected),max(0,project.pages.count-1));projectURL=url;unsaved=false;untitledChanged=false;noteRecent();updateTitle();undoStack=[];redoStack=[];thumbs=[:];previewThumbs=[:];turnedThumbs=[:];thumbnailPending=[:];thumbnailFailures=[:];pixelSizes=[:];reloadPages();selectCurrent();DispatchQueue.main.async{self.findMissingPhotographs()}}
    }
    @objc func locatePhotographs(){findMissingPhotographs();if Relink.missing(project.pages,exists:FileManager.default.fileExists(atPath:)).isEmpty {status.stringValue="Every photograph is where the project expects it"}}
    /// A project holds each photograph's full path. When some are gone, the project's own folder is tried first;
    /// then the user is asked for the folder they are in now, until all are found or the user stops.
    func findMissingPhotographs(){
        func exists(_ path:String)->Bool {var folder:ObjCBool=false;return FileManager.default.fileExists(atPath:path,isDirectory:&folder) && !folder.boolValue}
        var missing=Relink.missing(project.pages,exists:exists);guard !missing.isEmpty else{return}
        var found=hasProjectFile ? Relink.relink(&project.pages,in:projectURL.deletingLastPathComponent(),exists:exists):0
        missing=Relink.missing(project.pages,exists:exists)
        // A test run has nobody to answer.
        while !missing.isEmpty,testDirectory == nil {
            let first=URL(fileURLWithPath:project.pages[missing[0]].path)
            let alert=NSAlert();alert.messageText=missing.count==project.pages.count ? "The photographs of this project could not be found":"\(missing.count) of \(project.pages.count) photographs could not be found"
            alert.informativeText="They may have been moved or renamed, or be on a disk that is not connected. “\(first.lastPathComponent)” was expected in:\n\(first.deletingLastPathComponent().path)\n\nShow KettleStitch the folder the photographs are in now."
            alert.addButton(withTitle:"Locate Folder…");alert.addButton(withTitle:"Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else{break}
            let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.prompt="Use This Folder"
            panel.message="Choose the folder that holds “\(first.lastPathComponent)”, or a folder above it."
            guard panel.runModal() == .OK,let folder=panel.url else{break}
            let here=Relink.relink(&project.pages,in:folder,exists:exists);found+=here;missing=Relink.missing(project.pages,exists:exists)
            let unsure=Relink.ambiguous(project.pages,in:folder,exists:exists)
            if unsure>0 {
                let doubt=NSAlert();doubt.messageText="\(unsure) photograph\(unsure==1 ? " was":"s were") left alone because \(unsure==1 ? "its name fits":"their names fit") more than one page"
                doubt.informativeText="Several pages expect a photograph with the same file name from different folders, and “\(folder.lastPathComponent)” has only one of that name, so KettleStitch cannot tell whose it is. Choose a folder that still holds the photographs in the folders they were in, or the folder above those.";doubt.runModal()
            } else if here==0 {
                let none=NSAlert();none.messageText="None of the missing photographs are in “\(folder.lastPathComponent)”";none.informativeText="They are matched by file name, so they must still be called what they were.";none.runModal()
            }
        }
        guard found>0 else{return}
        thumbnailPending=[:];thumbnailFailures=[:];save();reloadPages();selectCurrent()
        status.stringValue="Found \(found) photograph\(found==1 ? "":"s")"+(missing.isEmpty ? "":" · \(missing.count) still missing — File ▸ Locate Missing Photographs")
    }
    /// Returns whether the project was saved to a file; false when the panel was cancelled or the save failed.
    @discardableResult @objc func saveAs(_ sender:Any?=nil)->Bool {
        let panel=NSSavePanel();panel.nameFieldStringValue="Book.kettlestitch";guard panel.runModal() == .OK,let url=panel.url else{return false}
        do{try project.save(url);projectURL=url;untitledChanged=false;write();status.stringValue="Saved \(url.lastPathComponent)";return true}catch{showError(error);return false}
    }

    // MARK: Background work
    func beginProgress(_ kind:ProgressTracker.Kind,_ total:Int){tracker.begin(kind,total:total);showProgress();noteActivity()}
    func stepProgress(_ kind:ProgressTracker.Kind,_ done:Int){tracker.advance(kind,to:done);showProgress()}
    func endProgress(_ kind:ProgressTracker.Kind){tracker.end(kind);showProgress();noteActivity()}
    // MARK: After a crash
    /// Changes the journal and writes it down, from any thread. A test run keeps none.
    func updateJournal(_ change:(inout CrashJournal)->Void){
        journalLock.lock();defer{journalLock.unlock()}
        let before=journal;change(&journal)
        if journal != before,journalKept,let support=supportURL {try? journal.write(in:support)}
    }
    func noteActivity(){
        let names:[(ProgressTracker.Kind,String)]=[(.export,"Exporting"),(.detect,"Proposing crops"),(.split,"Proposing splits or measuring tilt"),(.review,"Waiting for a second opinion")]
        let now=names.first{tracker.isRunning($0.0)}?.1
        updateJournal{$0.activity=now}
    }
    /// Deals with what a crashed run left: removes a half-written PDF, sets aside the photographs that were being
    /// read, and tells the user what happened and what was kept.
    func handleCrash(_ found:CrashJournal){
        if let partial=found.partialExport {
            // Only ever a file this app named as its own unfinished export.
            let url=URL(fileURLWithPath:partial)
            if url.lastPathComponent.hasPrefix(".partial-"),url.pathExtension=="pdf" {try? FileManager.default.removeItem(at:url)}
        }
        Imaging.hold(found.suspects)
        let kept=recoveryEntries().filter{$0.reason.needsAttention}.count,lines=found.account(recoverable:kept)
        status.stringValue="KettleStitch closed unexpectedly last time"+(lines.first.map{" · "+$0} ?? "")
        guard testDirectory == nil,!lines.isEmpty else{return}
        let alert=NSAlert();alert.messageText="KettleStitch closed unexpectedly last time";alert.informativeText=lines.joined(separator:"\n\n")
        let project=found.project.map{URL(fileURLWithPath:$0)}.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
        // With changes kept aside the Recovery window is the way back in; otherwise the project can be reopened here.
        if let project,kept==0,self.project.pages.isEmpty {alert.addButton(withTitle:"Reopen “\(project.deletingPathExtension().lastPathComponent)”");alert.addButton(withTitle:"Not Now")} else {alert.addButton(withTitle:"OK")}
        if alert.runModal() == .alertFirstButtonReturn,let project,kept==0,self.project.pages.isEmpty {open(project)}
    }
    /// Reads again the photographs set aside after a crash.
    @objc func tryHeldAgain(){
        let count=Imaging.heldCount;guard count>0 else{return}
        Imaging.release();thumbnailFailures=[:];thumbnailPending=[:]
        table.reloadData(forRowIndexes:IndexSet(integersIn:0..<project.pages.count),columnIndexes:IndexSet(integer:0))
        if current != nil,original == nil {loadCurrent()}
        status.stringValue="Reading \(count) set-aside photograph\(count==1 ? "":"s") again"
    }
    /// A copy of unsaved changes to this project file that a crash left, if there is one.
    func recoveryCopy(for url:URL)->RecoveryList.Entry? {
        recoveryEntries().first{$0.reason == .unsavedChanges && $0.originalPath.map{URL(fileURLWithPath:$0).standardizedFileURL.path}==url.standardizedFileURL.path}
    }
    /// Detection, export, Claude review and split proposals can overlap; the bar shows them together and hides when all are done.
    func showProgress(){
        progress.isHidden = !tracker.isActive;stopButton.isHidden = !tracker.isActive
        if tracker.isIndeterminate {progress.isIndeterminate=true;progress.startAnimation(nil)}
        else {progress.stopAnimation(nil);progress.isIndeterminate=false;progress.maxValue=1;progress.doubleValue=tracker.fraction}
    }
    @objc func detectCurrent(){guard let i=current else{return};runDetection([i])}
    /// Pages nothing has been proposed for yet, and those whose photograph could not be read the last time.
    @objc func detectPending(){runDetection(project.pages.indices.filter{project.pages[$0].status=="Pending" || project.pages[$0].status==AppDelegate.detectionError})}
    static let detectionError="Detection error"
    func runDetection(_ indexes:[Int]){
        guard !detecting,!indexes.isEmpty else{return};detecting=true;let token=generation
        let snapshots=indexes.map{($0,project.pages[$0])}
        beginProgress(.detect,snapshots.count)
        var failures=0,trouble=""
        for (number,item) in snapshots.enumerated(){let (index,page)=item
            queue.addOperation{[weak self] in
                let result:Result<[Candidate],Error>=autoreleasepool{Result {try Detector().detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600))}}
                DispatchQueue.main.async {guard let self,self.generation==token else{return}
                    if let i=self.project.pages.firstIndex(where:{$0.id==page.id}),self.project.pages[i].revision==page.revision {
                        switch result {
                        case .success(let found):
                            self.project.pages[i].candidates=Candidate.merging(detected:found,into:self.project.pages[i].candidates)
                            if self.project.pages[i].status=="Pending" || self.project.pages[i].status==AppDelegate.detectionError {
                                if let best=found.first {self.project.pages[i].quad=best.quad;self.project.pages[i].status="Check proposal"}else{self.project.pages[i].status="No boundary — crop manually"}
                            }
                        // A crop the user made stands, and keeps saying what it is, when detection cannot read the photograph.
                        case .failure(let error):if self.project.pages[i].status=="Pending" {self.project.pages[i].status=AppDelegate.detectionError};failures+=1;trouble=error.localizedDescription
                        }
                        self.save();self.table.reloadData(forRowIndexes:IndexSet(integer:index),columnIndexes:IndexSet(integer:0))
                        if self.current==i {self.canvas.quad=self.project.pages[i].quad;self.refreshDetail();if self.canvas.preview {self.renderPreview()}}
                    }
                    self.status.stringValue="Detection \(number+1)/\(snapshots.count) · review every proposal";self.stepProgress(.detect,number+1)
                    if number==snapshots.count-1 {
                        self.detecting=false;self.endProgress(.detect)
                        if failures>0 {self.status.stringValue="\(failures) photograph\(failures==1 ? "":"s") could not be read (\(trouble)) · Detect All Pending Pages tries \(failures==1 ? "it":"them") again"}
                    }
                }
            }
        }
    }
    @objc func stop(){invalidateWork();exportCancelled=true;reviewCancelled=true;reviewTask?.cancel();status.stringValue="Stopped; what was finished is kept in the project"}
    @objc func exportImages(){
        guard !exporting,!project.pages.isEmpty else{return}
        let selected=targetIndexes
        let sheet=ExportSheetController(options:exportOptions,selectedCount:selected.count,totalCount:project.pages.count);exportSheet=sheet
        sheet.begin(on:window){[weak self] options,selectedOnly in
            guard let self else{return};self.exportSheet=nil
            guard let options else{return}
            self.exportOptions=options;if let data=try? JSONEncoder().encode(options){UserDefaults.standard.set(data,forKey:"exportOptions")}
            let pages=selectedOnly ? selected.filter{self.project.pages.indices.contains($0)}.map{self.project.pages[$0]}:self.project.pages
            // How picture zones are kept is fixed now, so a change in Settings while the export runs cannot divide it.
            var fixed=options;fixed.zoneMode=Imaging.pictureZoneMode
            DispatchQueue.main.async{self.chooseDestination(pages,fixed)}
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
        // Counted in pages as they come out: a split spread is two, unless the export ignores splits.
        let parts=pages.map{Exporter.quads(for:$0,options:options).count},total=parts.reduce(0,+)
        exportCancelled=false;exporting=true;beginProgress(.export,total);status.stringValue="Exporting 0/\(total)"
        exportQueue.addOperation{[weak self] in
            var completed=0
            func cancelled()->Bool {DispatchQueue.main.sync{self?.exportCancelled ?? true}}
            func report(_ index:Int){completed+=parts[index];let done=completed;DispatchQueue.main.async{self?.status.stringValue="Exporting \(done)/\(total)";self?.stepProgress(.export,done)}}
            self?.updateJournal{$0.exportDestination=destination.path}
            defer{self?.updateJournal{$0.exportDestination=nil;$0.partialExport=nil}}
            var informationLeft:[String]=[]
            do{
                var finished=true
                if options.format == .pdf {
                    let temp=destination.deletingLastPathComponent().appendingPathComponent(".partial-\(UUID().uuidString).pdf")
                    self?.updateJournal{$0.partialExport=temp.path}
                    do{
                        let writer=try PDFWriter(url:temp,password:options.password)
                        for (i,page) in pages.enumerated() {if cancelled(){finished=false;break};try autoreleasepool{try writer.add(page,options:options)};report(i)}
                        // Closing and moving a long PDF takes a while after the last page is drawn.
                        if finished {DispatchQueue.main.async{self?.status.stringValue="Finishing the PDF…";self?.beginProgress(.export,1)}}
                        try writer.close();informationLeft=writer.informationLeft
                        if finished {
                            // An existing PDF is exchanged for the new one in a single step, so it is never gone without its replacement.
                            if FileManager.default.fileExists(atPath:destination.path) {_=try FileManager.default.replaceItemAt(destination,withItemAt:temp)}
                            else {try FileManager.default.moveItem(at:temp,to:destination)}
                        } else {try? FileManager.default.removeItem(at:temp)}
                    }catch{try? FileManager.default.removeItem(at:temp);throw error}
                } else {
                    for (i,page) in pages.enumerated(){if cancelled(){finished=false;break}
                        try autoreleasepool{
                            let name=String(format:"%04d-",i+1)+URL(fileURLWithPath:page.path).deletingPathExtension().lastPathComponent
                            try Exporter.writeImages(page,in:destination,name:name,options:options)
                        };report(i)
                    }
                }
                let done=completed,complete=finished,left=informationLeft
                DispatchQueue.main.async{guard let self else{return};self.exporting=false;self.endProgress(.export)
                    self.status.stringValue=complete ? "Exported \(done) pages to \(destination.lastPathComponent)":options.format == .pdf ? "Export stopped; no PDF was written":"Export stopped after \(done)/\(total)"
                    // The PDF is whole, but says more about how it was made than it should.
                    if complete,!left.isEmpty {
                        self.status.stringValue+=" · its document information could not be removed (\(left.joined(separator:", ")))"
                        if self.testDirectory == nil {
                            let alert=NSAlert();alert.messageText="The PDF was exported, but its document information could not be removed"
                            alert.informativeText="It still holds: \(left.joined(separator:", ")). macOS writes its own version and the time of export there. KettleStitch normally removes them and could not on this version of macOS; please report this.";alert.runModal()
                        }
                    }
                    if complete,self.testDirectory == nil {NSWorkspace.shared.activateFileViewerSelecting([destination])}
                }
            }catch{DispatchQueue.main.async{self?.exporting=false;self?.endProgress(.export);self?.showError(error)}}
        }
    }

    // MARK: Claude
    /// Keeps the photograph on screen with its crop and split as they stand, for working out later why the
    /// detector got them wrong. Everything goes into one new folder under "Bad Examples" in the support folder.
    @objc func saveBadExample(){
        guard let i=current else{NSSound.beep();return}
        let page=project.pages[i],source=URL(fileURLWithPath:page.path)
        let stamp=DateFormatter();stamp.locale=Locale(identifier:"en_US_POSIX");stamp.dateFormat="yyyy-MM-dd HH.mm.ss"
        let folder=usageURL.deletingLastPathComponent().appendingPathComponent("Bad Examples").appendingPathComponent(stamp.string(from:Date())+" "+source.deletingPathExtension().lastPathComponent)
        do{
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:source,to:folder.appendingPathComponent(source.lastPathComponent))
            // The same reduced picture with the crop and split drawn on it that Claude is shown.
            let photo=try Imaging.load(source,maxPixel:1568)
            try Exporter.encode(ClaudeReview.overlay(photo,quad:page.quad,split:ClaudeReview.splitEnds(page)),as:.jpeg,quality:0.85,dpi:nil).write(to:folder.appendingPathComponent("overlay.jpg"))
            // The example may be handed to someone else to look at, so it names files without the folders they are in.
            func named(_ page:Page)->Page {var copy=page;copy.path=URL(fileURLWithPath:page.path).lastPathComponent;return copy}
            let example=BadExample(saved:Date(),app:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build",photograph:source.lastPathComponent,number:i+1,of:project.pages.count,
                note:"The crop and split below are as the user left them when marking this page as a bad example. Coordinates are fractions of the photograph from its top-left corner; a split is a fraction across the crop at its top and bottom edges. overlay.jpg shows them drawn on the photograph.",
                page:named(page),previous:i>0 ? named(project.pages[i-1]):nil,splitGuide:SplitDetector.guide(for:i,in:project.pages))
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(example).write(to:folder.appendingPathComponent("example.json"),options:.atomic)
            status.stringValue="Saved a bad example to \(folder.path)"
            if testDirectory == nil {NSWorkspace.shared.activateFileViewerSelecting([folder])}
        }catch{showError(error)}
    }
    var currentVersion:String {Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"}
    /// Asks GitHub for the latest release. `done` gets it on the main thread, or nil with the reason it could not be had.
    func fetchLatestRelease(_ done:@escaping(UpdateCheck.Release?,String)->Void){
        ReviewAPI.session.dataTask(with:UpdateCheck.request()){data,response,error in
            let code=(response as? HTTPURLResponse)?.statusCode ?? 0
            let release=code==200 ? data.flatMap(UpdateCheck.latest(from:)):nil
            DispatchQueue.main.async{done(release,error?.localizedDescription ?? "GitHub did not answer as expected (\(code)).")}
        }.resume()
    }
    /// Asks for the latest release and says whether it is newer than this copy, from the menu.
    @objc func checkForUpdates(){
        let current=currentVersion
        status.stringValue="Checking for updates…"
        fetchLatestRelease{[weak self] release,problem in guard let self else{return}
            let alert=NSAlert()
            if let release,UpdateCheck.isNewer(release.version,than:current) {
                self.status.stringValue="KettleStitch \(release.version) is available"
                alert.messageText="KettleStitch \(release.version) is available";alert.informativeText="You have \(current). The download page says what is new and has the disk images."
                alert.addButton(withTitle:"Open Download Page");alert.addButton(withTitle:"Later")
                if alert.runModal() == .alertFirstButtonReturn {NSWorkspace.shared.open(release.page)}
            } else if release != nil {
                self.status.stringValue="KettleStitch \(current) is the latest version"
                alert.messageText="You have the latest version";alert.informativeText="KettleStitch \(current) is the newest release.";alert.runModal()
            } else {
                self.status.stringValue="Could not check for updates"
                alert.messageText="Could not check for updates";alert.informativeText=problem+" You can look at the releases page yourself."
                alert.addButton(withTitle:"Open Releases Page");alert.addButton(withTitle:"Cancel")
                if alert.runModal() == .alertFirstButtonReturn,let page=URL(string:UpdateCheck.releasesPage) {NSWorkspace.shared.open(page)}
            }
        }
    }
    /// With "Check for updates on startup" on in Settings, one quiet check at launch. A newer version is mentioned
    /// in the status bar and nothing else happens; a failure, or being up to date, says nothing.
    func checkForUpdatesAtStartup(){
        guard testDirectory == nil,UserDefaults.standard.bool(forKey:SettingsController.startupUpdateKey) else{return}
        let current=currentVersion
        fetchLatestRelease{[weak self] release,_ in
            guard let self,let release,UpdateCheck.isNewer(release.version,than:current) else{return}
            self.status.stringValue="KettleStitch \(release.version) is available · KettleStitch ▸ Check for Updates… opens the download page"
        }
    }
    @objc func showUsageLog(){
        if usageLog == nil {usageLog=UsageLogController(url:usageURL)}
        usageLog!.show()
    }
    @objc func showSettings(){
        if settings == nil {
            settings=SettingsController()
            settings!.keys.bindings={[weak self] in self?.keyBindings ?? KeyBindings()}
            settings!.keys.change={[weak self] in self?.setKeyBindings($0)}
            // A change to how picture zones are kept shows at once, in the preview and in the sidebar's pictures.
            settings!.onChange={[weak self] in guard let self else{return}
                self.previewThumbs=[:];self.table.reloadData(forRowIndexes:IndexSet(integersIn:0..<self.project.pages.count),columnIndexes:IndexSet(integer:0))
                if self.canvas.preview {self.renderPreview()}
            }
        }
        settings!.show()
    }
    /// Asks Claude to judge the crop of every targeted page. A fix is selected at once and stays among the proposals; Undo puts the old crop back.
    @objc func sendToClaude(){
        let targets=targetIndexes;guard !reviewing,!targets.isEmpty else{return}
        // The key goes from the keychain to the request for this provider and nowhere else: it is not logged, saved or shown.
        let model=ReviewChoice.model,reviewer=model.provider.name
        guard let key=Keychain.read(model.provider),!key.isEmpty else{showSettings();if Keychain.replacedSinceLaunch {settings?.explain(Keychain.reopenAdvice);return};settings?.explain("Add \(model.provider.company == "Anthropic" ? "an":"a") \(model.provider.company) API key to send crops to \(reviewer).");return}
        let pages=targets.map{project.pages[$0]},token=generation
        beginReview(pages,model:ReviewChoice.displayName(model))
        reviewQueue.addOperation{[weak self] in
            var good=0,fixes=0,failure:Error?,spent:ReviewUsage?
            for (number,page) in pages.enumerated() {
                let proceed=DispatchQueue.main.sync{()->Bool in
                    guard let self,!self.reviewCancelled,self.generation==token else{return false}
                    self.reviewWaiting(for:page,number:number+1);return true
                }
                if !proceed{break}
                let asked=Date()
                let result=Result{try ClaudeReview.run(page,model:model,apiKey:key){task in DispatchQueue.main.async{self?.reviewTask=task}}}
                var stop=false
                DispatchQueue.main.sync{
                    guard let self,self.generation==token,!self.reviewCancelled else{stop=true;return}
                    self.stepProgress(.review,number+1)
                    switch result {
                    case .failure(let error):failure=error;stop=true
                    case .success(let review):
                        if review.quad != nil{fixes+=1}else if review.good{good+=1}
                        self.reviewPending.remove(page.id);self.reviewActive=nil
                        self.record(review,for:page,done:number+1,of:pages.count,reviewer:reviewer)
                        if let usage=review.usage {
                            spent=(spent ?? ReviewUsage())+usage
                            try? UsageLog.append(UsageEntry(date:asked,file:URL(fileURLWithPath:page.path).lastPathComponent,model:self.reviewModel,seconds:Date().timeIntervalSince(asked),usage:usage),to:self.usageURL)
                            self.usageLog?.reload()
                            if pages.count==1 {self.status.stringValue += " · "+usage.summary}
                        }
                    }
                }
                if stop{break}
            }
            DispatchQueue.main.async{guard let self else{return}
                let stopped=self.reviewCancelled;self.endReview()
                if let failure,!stopped {self.status.stringValue="\(reviewer) review failed";self.showError(failure)}
                else if stopped {self.status.stringValue="Stopped; \(reviewer)'s finished reviews are kept"}
                else if pages.count>1 {self.status.stringValue="\(reviewer) reviewed \(good+fixes) of \(pages.count): \(good) good, \(fixes) fixed — Undo on a page puts its old crop back"+(spent.map{" · "+$0.summary} ?? "")}
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
        reviewTimer?.invalidate();reviewTimer=nil;reviewing=false;reviewTask=nil;reviewPending=[];reviewActive=nil
        endProgress(.review)
        reloadReviewRows(waiting)
    }
    func record(_ review:CropReview,for page:Page,done:Int,of total:Int,reviewer:String=Candidate.claudeSource){
        guard let i=project.pages.firstIndex(where:{$0.id==page.id}) else{return}
        // Claude saw the crop as it was when sent; a verdict on a crop edited since would mislead.
        let before=project.pages[i]
        guard project.pages[i].record(review,sentQuad:page.quad,sentSplit:page.split,sentRotation:page.rotation,reviewer:reviewer) else{
            if total==1 {status.stringValue="The crop changed while \(reviewer) was looking, so its answer was not kept"}
            return
        }
        save();table.reloadData(forRowIndexes:IndexSet(integer:i),columnIndexes:IndexSet(integer:0))
        // Claude's crop and split line are applied as they arrive; Undo puts the page back as it was.
        let moved=project.pages[i].split != before.split
        if moved || project.pages[i].quad != before.quad {undoStack.append(.pages([before]));redoStack.removeAll()}
        if current==i {canvas.quad=project.pages[i].quad;refreshDetail();if canvas.preview{renderPreview()}}
        if total==1 {status.stringValue=(review.quad != nil ? "\(reviewer)’s fix is selected · Undo puts the old crop back":review.good ? "\(reviewer): crop looks right":"\(reviewer): no usable fix")+(moved ? " · \(reviewer) moved the split line (Undo puts it back)":"")}
    }

    func showError(_ error:Error){let alert=NSAlert(error:error);alert.runModal()}
    @objc func cornerSegment(_ sender:NSSegmentedControl){selectCorner([0,1,3,2][sender.selectedSegment])}
    /// `i` is the corner as seen, clockwise from top-left; the canvas wants the stored one.
    func selectCorner(_ i:Int,keyboard:Bool=false){if canvas.preview{setPreview(false)};canvas.selectCorner(canvas.turn.storedCorner(seenAt:i),keyboard:keyboard);window.makeFirstResponder(canvas)}
    func handleKey(_ e:NSEvent)->Bool {
        guard !e.modifierFlags.contains(.command),!e.modifierFlags.contains(.control),let typed=e.charactersIgnoringModifiers?.lowercased() else{return false}
        // What follows is written for the default keys. A key the user has given to a command arrives here as that
        // command's default key; a key whose command has moved away does nothing.
        var key=typed,shift=e.modifierFlags.contains(.shift),option=e.modifierFlags.contains(.option)
        switch keyBindings.translate(KeyStroke(key:typed,shift:shift,option:option)) {
        case .run(let stroke):key=stroke.key;shift=stroke.shift;option=stroke.option
        case .nothing:return false
        case .unchanged:break
        }
        if [123,124,125,126].contains(e.keyCode),canvas.keyboardSelection {let mapping:[UInt16:String]=[123:"a",124:"d",125:"s",126:"w"];canvas.nudge(mapping[e.keyCode]!,large:shift);return true}
        if ["h","j","k","l"].contains(key) {
            if option {
                guard let i=current else{return true}
                let step=shift ? 0.02:0.005
                let delta=ViewTurn(project.pages[i].rotation).photographDelta(Point(key=="h" ? -step:key=="l" ? step:0,key=="k" ? -step:key=="j" ? step:0))
                if let q=project.pages[i].quad.translated(by:delta),q != project.pages[i].quad {
                    edit{$0.setManualCrop(q)}
                }
            } else {resizeSide(key,inward:shift)}
            return true
        }
        switch key {
        case "b" where shift:option ? removeSmudges():toggleSmudge()
        case "c" where shift:option ? removeClones():toggleClone()
        case "g":newProject();case "i":importImages();case "o":openProject();case "s":if shift {saveAs()} else {saveProject()}
        case "d":targetIndexes.count>1 ? detectPending():detectCurrent();case "b":detectPending();case "e":exportImages()
        case "p":togglePreview()
        case "r":shift ? rotateLeft():rotate()
        case "a":sendToClaude();case "m":toggleFlag()
        case "t" where option && !shift:proposeAllSplits()
        case "t":shift ? removeSplit():proposeSplit()
        case "v" where !shift:copyPreviousAdjustments()
        // The split moves with y and u, which sit side by side; comma is free, and period goes to the next unusual page.
        case "y":moveSplit(shift ? -0.01:-0.002)
        case "u":moveSplit(shift ? 0.01:0.002)
        case "/" where option:nextDeskewHalf()
        case "," where option:turnDeskew(-0.1)
        case "." where option:turnDeskew(0.1)
        case "." where !shift:nextOutlier()
        case "q":shift ? removeDeskew():deskew()
        case "w":shift ? removeZones():addZone()
        case "f","0":fit();case "+","=":zoomIn();case "-":zoomOut();case "c":copyPrevious();case ";":shrinkCrop();case "'":expandCrop();case "x":resetCrop();case "z":if shift {redo()} else {undo()}
        case "n":nextReview();case "[":cycleCandidate(-1);case "]":cycleCandidate(1)
        case "1","2","3","4":selectCorner([0,1,3,2][Int(key)!-1],keyboard:true)
        case "5","6","7","8":if canvas.preview{setPreview(false)};canvas.selectEdge(canvas.turn.storedEdge(seenAt:[0,3,1,2][Int(key)!-5]),keyboard:true);window.makeFirstResponder(canvas)
        case "?","/":help()
        default:
            if e.keyCode==53 {if canvas.smudgeMode{setSmudging(false)}else if canvas.cloneMode{setCloning(false)}else if canvas.zoneMode{canvas.zoneMode=false;status.stringValue="Picture zone cancelled"}else if canvas.hasSelection{canvas.releaseCorner()}else{stop()}}
            else if e.keyCode==123 {navigate(-1)}
            else if e.keyCode==124 {
                // With Shift the crop comes along: the same as stepping on and pressing C.
                let from=current;navigate(1)
                if shift,current != from {copyPrevious()}
            }
            else if e.keyCode==36{accept()}
            else if e.keyCode==115 {firstPage()}else if e.keyCode==119{lastPage()}
            else if e.keyCode==116{navigate(-10)}else if e.keyCode==121{navigate(10)}else{return false}
        }
        return true
    }
    @objc func help(){if shortcuts == nil {shortcuts=ShortcutsController(bindings:keyBindings)};shortcuts!.show()}
    /// Takes the user's choice of keys into use everywhere they show: the menus, the inspector's list and the reference.
    func setKeyBindings(_ bindings:KeyBindings){
        keyBindings=bindings
        if testDirectory == nil,let data=try? bindings.encode() {UserDefaults.standard.set(data,forKey:KeyBindings.key)}
        applyKeyBindings()
    }
    func applyKeyBindings(){
        func visit(_ menu:NSMenu){
            for item in menu.items {
                if let sub=item.submenu {visit(sub)}
                // Only keys shown on their own are the bindings' to set; Command shortcuts stay as they are.
                guard item.target === self,let action=item.action,let id=AppDelegate.keySelectors[action],item.keyEquivalentModifierMask.isDisjoint(with:[.command,.control]),let stroke=keyBindings.stroke(for:id) else{continue}
                var mask:NSEvent.ModifierFlags=[];if stroke.shift{mask.insert(.shift)};if stroke.option{mask.insert(.option)}
                item.keyEquivalent=stroke.key;item.keyEquivalentModifierMask=mask
            }
        }
        if let main=NSApp.mainMenu {visit(main)}
        for (label,entry) in zip(shortcutKeyLabels,ShortcutReference.brief(with:keyBindings)) {label.0.stringValue=entry.keys;label.1.stringValue=entry.action}
        shortcuts?.window.close();shortcuts=nil
    }
    /// The menu command each changeable key belongs to, where it has one.
    static let keySelectors:[Selector:String]=[
        #selector(importImages):"import",#selector(exportImages):"export",#selector(copyPreviousAdjustments):"copyImageSettings",#selector(nextReview):"nextUnreviewed",#selector(nextOutlier):"nextUnusual",#selector(toggleFlag):"flag",
        #selector(rotateLeft):"rotateLeft",#selector(rotate):"rotateRight",#selector(detectCurrent):"detect",#selector(detectPending):"detectPending",#selector(nextCandidate):"nextProposal",#selector(previousCandidate):"previousProposal",
        #selector(resetCrop):"fullImage",#selector(copyPrevious):"copyCrop",#selector(proposeSplit):"split",#selector(removeSplit):"removeSplit",#selector(proposeAllSplits):"splitAll",#selector(moveSplitLeft):"splitLeft",#selector(moveSplitRight):"splitRight",
        #selector(deskew):"deskew",#selector(removeDeskew):"removeDeskew",#selector(deskewCounterclockwise):"deskewCounterclockwise",#selector(deskewClockwise):"deskewClockwise",#selector(nextDeskewHalf):"deskewHalf",#selector(addZone):"zone",#selector(removeZones):"removeZones",
        #selector(toggleSmudge):"smudge",#selector(removeSmudges):"removeSmudges",#selector(toggleClone):"clone",#selector(removeClones):"removeClones",#selector(sendToClaude):"secondOpinion",#selector(togglePreview):"preview",
        #selector(zoomIn):"zoomIn",#selector(zoomOut):"zoomOut",#selector(fit):"fit",#selector(help):"help"]
}
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let delegate=AppDelegate()
app.delegate=delegate
app.run()

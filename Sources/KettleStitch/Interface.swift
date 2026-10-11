import AppKit
import CropCore

/// Opaque window-coloured backing for panes beside the canvas.
final class PaneView: NSView {
    // Fill only this view. Since macOS 14 a view is not clipped to its bounds and the dirty rectangle can
    // reach beyond them, so filling that would paint over neighbouring views such as the canvas.
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();bounds.fill()}
}

/// A right-click acts on the row under the pointer, as in Finder, by making it the selection first.
final class PageTable: NSTableView {
    override func menu(for event:NSEvent)->NSMenu? {
        let row=self.row(at:convert(event.locationInWindow,from:nil))
        let wanted=SelectionPolicy.contextSelection(clicked:row,selected:selectedRowIndexes,count:numberOfRows)
        if wanted != selectedRowIndexes {selectRowIndexes(wanted,byExtendingSelection:false)}
        return super.menu(for:event)
    }
}

/// A sidebar picture of a page as export will render it, with the settings it was made from.
final class PreviewThumbnail {
    let image:NSImage,look:String
    init(_ image:NSImage,_ look:String){self.image=image;self.look=look}
    static func look(_ p:Page)->String {"\(p.quad)|\(p.rotation)|\(String(describing:p.adjustments))|\(String(describing:p.split))|\(String(describing:p.deskew))|\(String(describing:p.pictureZones))|\(String(describing:p.smudges))"}
}
/// A small rounded label, used for a photograph's file type beside its name.
final class PillLabel: NSTextField {
    convenience init(){
        self.init(labelWithString:"");font = .systemFont(ofSize:8.5,weight:.semibold);textColor = .secondaryLabelColor;alignment = .center
        setContentHuggingPriority(.required,for:.horizontal);setContentCompressionResistancePriority(.required,for:.horizontal)
    }
    override var intrinsicContentSize: NSSize {let size=super.intrinsicContentSize;return stringValue.isEmpty ? .zero:NSSize(width:size.width+7,height:size.height+1)}
    override func draw(_ dirtyRect:NSRect){
        NSColor.labelColor.withAlphaComponent(0.12).setFill();NSBezierPath(roundedRect:bounds,xRadius:3.5,yRadius:3.5).fill()
        super.draw(dirtyRect)
    }
}
final class PageCell: NSTableCellView {
    static let identifier=NSUserInterfaceItemIdentifier("page")
    let thumb=NSImageView()
    let title=NSTextField(labelWithString:"")
    let subtitle=NSTextField(labelWithString:"")
    let kind=PillLabel()
    let flag=NSImageView()
    let spinner=NSProgressIndicator()
    init(){
        super.init(frame:.zero);identifier=PageCell.identifier
        thumb.imageScaling = .scaleProportionallyUpOrDown;thumb.wantsLayer=true;thumb.layer?.cornerRadius=3;thumb.layer?.masksToBounds=true
        title.font = .systemFont(ofSize:12);title.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize:11);subtitle.lineBreakMode = .byTruncatingTail
        flag.image=symbol("flag.fill");flag.contentTintColor = .systemOrange
        spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
        for v in [thumb,title,subtitle,kind,flag,spinner] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;addSubview(v)}
        for label in [title,subtitle] {label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)}
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo:leadingAnchor,constant:2),thumb.centerYAnchor.constraint(equalTo:centerYAnchor),thumb.widthAnchor.constraint(equalToConstant:44),thumb.heightAnchor.constraint(equalToConstant:46),
            title.leadingAnchor.constraint(equalTo:thumb.trailingAnchor,constant:8),title.bottomAnchor.constraint(equalTo:centerYAnchor,constant:-1),kind.leadingAnchor.constraint(equalTo:title.trailingAnchor,constant:5),kind.centerYAnchor.constraint(equalTo:title.centerYAnchor),kind.trailingAnchor.constraint(lessThanOrEqualTo:flag.leadingAnchor,constant:-4),
            subtitle.leadingAnchor.constraint(equalTo:title.leadingAnchor),subtitle.topAnchor.constraint(equalTo:centerYAnchor,constant:1),subtitle.trailingAnchor.constraint(lessThanOrEqualTo:flag.leadingAnchor,constant:-4),
            spinner.centerXAnchor.constraint(equalTo:thumb.centerXAnchor),spinner.centerYAnchor.constraint(equalTo:thumb.centerYAnchor),
            flag.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-2),flag.centerYAnchor.constraint(equalTo:centerYAnchor),flag.widthAnchor.constraint(equalToConstant:13),flag.heightAnchor.constraint(equalToConstant:13)])
    }
    required init?(coder:NSCoder){nil}
    func show(_ page:Page,number:Int,thumbnail:NSImage?,unusual:String?=nil,review:ReviewProgress.State?=nil){
        thumb.image=thumbnail;flag.isHidden=page.flagged != true
        // The photograph Claude is looking at dims under a spinner; queued ones only say so.
        thumb.alphaValue=review == nil ? 1:0.35
        if review == .active {spinner.startAnimation(nil)} else {spinner.stopAnimation(nil)}
        // The file type sits in a pill, so the name itself has more room.
        let file=URL(fileURLWithPath:page.path)
        title.stringValue="\(number). \(file.deletingPathExtension().lastPathComponent)"
        kind.stringValue=file.pathExtension.uppercased();kind.invalidateIntrinsicContentSize();kind.isHidden=kind.stringValue.isEmpty
        let proposed=page.candidates.contains{$0.source==Candidate.claudeSource}
        subtitle.stringValue=review?.label ?? (page.reviewed ? "✓ Reviewed":page.status)+(proposed ? " · Claude fix":"")+(page.split != nil ? " · split":"")+(unusual.map{" · ⚠︎ "+$0} ?? "")
        subtitle.textColor=review != nil ? .controlAccentColor:page.reviewed ? .systemGreen:.secondaryLabelColor
    }
}

extension NSToolbarItem.Identifier {
    static let importPhotos=NSToolbarItem.Identifier("import"),detect=NSToolbarItem.Identifier("detect"),detectPending=NSToolbarItem.Identifier("detectPending")
    static let rotateLeft=NSToolbarItem.Identifier("rotateLeft"),rotateRight=NSToolbarItem.Identifier("rotateRight"),preview=NSToolbarItem.Identifier("preview"),zoom=NSToolbarItem.Identifier("zoom")
    static let split=NSToolbarItem.Identifier("split"),flag=NSToolbarItem.Identifier("flag"),accept=NSToolbarItem.Identifier("accept"),claude=NSToolbarItem.Identifier("claude"),export=NSToolbarItem.Identifier("export"),inspector=NSToolbarItem.Identifier("inspector")
}

extension AppDelegate: NSWindowDelegate, NSDraggingDestination {
    func windowShouldClose(_ sender:NSWindow)->Bool {confirmUnsaved()}
    func droppedFiles(_ sender:NSDraggingInfo)->[URL] {
        (sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
    }
    /// The whole window accepts photographs, folders and project files.
    func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        droppedFiles(sender).contains{ImportPolicy.isPhotograph($0) || ImportPolicy.isProject($0) || $0.hasDirectoryPath} && window.attachedSheet==nil ? .copy:[]
    }
    func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        let files=droppedFiles(sender);guard !files.isEmpty else{return false}
        // Let the drag finish before any alert or long import starts.
        DispatchQueue.main.async{self.receive(files)};return true
    }
}

extension AppDelegate: NSToolbarDelegate {
    func buildUI() {
        window=NSWindow(contentRect:NSRect(x:100,y:100,width:1360,height:860),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.minSize=NSSize(width:980,height:760);window.toolbarStyle = .unified;window.collectionBehavior.insert(.fullScreenPrimary)
        let sidebar=NSViewController();sidebar.view=buildSidebar()
        let content=NSViewController();content.view=buildContent()
        let inspector=NSViewController();inspector.view=buildInspector()
        sidebarItem=NSSplitViewItem(sidebarWithViewController:sidebar);sidebarItem.minimumThickness=200;sidebarItem.maximumThickness=340
        let main=NSSplitViewItem(viewController:content);main.minimumThickness=460
        inspectorItem=NSSplitViewItem(viewController:inspector);inspectorItem.minimumThickness=304;inspectorItem.maximumThickness=304;inspectorItem.canCollapse=true;inspectorItem.holdingPriority=NSLayoutConstraint.Priority(260)
        for item in [sidebarItem!,main,inspectorItem!] {split.addSplitViewItem(item)}
        window.contentViewController=split;window.setContentSize(NSSize(width:1360,height:860));window.center()
        if testDirectory == nil {split.splitView.autosaveName="KettleStitchSplit";window.setFrameAutosaveName("KettleStitchWindow")}
        let toolbar=NSToolbar(identifier:"KettleStitchToolbar");toolbar.delegate=self;toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization=true;toolbar.autosavesConfiguration=testDirectory == nil
        window.toolbar=toolbar
    }
    func buildSidebar()->NSView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.documentView=table
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("page")));table.headerView=nil;table.rowHeight=58;table.style = .sourceList
        table.delegate=self;table.dataSource=self;table.allowsEmptySelection=false;table.allowsMultipleSelection=true
        let menu=NSMenu()
        for (title,action) in [("Add or Remove Flag",#selector(toggleFlag)),("Detect Cropping Frame",#selector(detectCurrent)),("Send to Claude",#selector(sendToClaude)),("Copy Settings",#selector(copySettings)),("Paste Settings",#selector(pasteSettings)),("Remove from Project",#selector(removePages))] {menu.addItem(withTitle:title,action:action,keyEquivalent:"").target=self}
        table.menu=menu
        return scroll
    }
    func buildContent()->NSView {
        let root=NSView(),bar=PaneView(),line=NSBox();line.boxType = .separator
        status.lineBreakMode = .byTruncatingTail;status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        counter.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular);counter.textColor = .secondaryLabelColor;counter.setContentHuggingPriority(.required,for:.horizontal)
        progress.isIndeterminate=false;progress.controlSize = .small;progress.isHidden=true
        stopButton.image=symbol("xmark.circle.fill");stopButton.isBordered=false;stopButton.toolTip="Stop (Esc)";stopButton.target=self;stopButton.action=#selector(stop);stopButton.isHidden=true
        for v in [canvas,bar] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        banner.material = .hudWindow;banner.blendingMode = .withinWindow;banner.state = .active;banner.wantsLayer=true;banner.layer?.cornerRadius=12;banner.layer?.masksToBounds=true;banner.isHidden=true
        bannerSpinner.style = .spinning;bannerSpinner.controlSize = .regular;bannerSpinner.isDisplayedWhenStopped=false
        bannerLabel.font = .systemFont(ofSize:15,weight:.medium);bannerLabel.textColor = .labelColor
        let notice=NSStackView(views:[bannerSpinner,bannerLabel]);notice.spacing=12;notice.translatesAutoresizingMaskIntoConstraints=false
        banner.translatesAutoresizingMaskIntoConstraints=false;banner.addSubview(notice);root.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo:canvas.centerXAnchor),banner.centerYAnchor.constraint(equalTo:canvas.centerYAnchor),
            notice.topAnchor.constraint(equalTo:banner.topAnchor,constant:18),notice.bottomAnchor.constraint(equalTo:banner.bottomAnchor,constant:-18),
            notice.leadingAnchor.constraint(equalTo:banner.leadingAnchor,constant:24),notice.trailingAnchor.constraint(equalTo:banner.trailingAnchor,constant:-24)])
        for v in [line,status,progress,stopButton,counter] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;bar.addSubview(v)}
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo:root.safeAreaLayoutGuide.topAnchor),canvas.leadingAnchor.constraint(equalTo:root.leadingAnchor),canvas.trailingAnchor.constraint(equalTo:root.trailingAnchor),canvas.bottomAnchor.constraint(equalTo:bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo:root.leadingAnchor),bar.trailingAnchor.constraint(equalTo:root.trailingAnchor),bar.bottomAnchor.constraint(equalTo:root.bottomAnchor),bar.heightAnchor.constraint(equalToConstant:28),
            line.topAnchor.constraint(equalTo:bar.topAnchor),line.leadingAnchor.constraint(equalTo:bar.leadingAnchor),line.trailingAnchor.constraint(equalTo:bar.trailingAnchor),
            status.leadingAnchor.constraint(equalTo:bar.leadingAnchor,constant:12),status.centerYAnchor.constraint(equalTo:bar.centerYAnchor),progress.leadingAnchor.constraint(equalTo:status.trailingAnchor,constant:10),
            progress.widthAnchor.constraint(equalToConstant:140),progress.centerYAnchor.constraint(equalTo:bar.centerYAnchor),stopButton.leadingAnchor.constraint(equalTo:progress.trailingAnchor,constant:6),
            stopButton.centerYAnchor.constraint(equalTo:bar.centerYAnchor),stopButton.trailingAnchor.constraint(lessThanOrEqualTo:counter.leadingAnchor,constant:-12),
            counter.trailingAnchor.constraint(equalTo:bar.trailingAnchor,constant:-12),counter.centerYAnchor.constraint(equalTo:bar.centerYAnchor)])
        return root
    }

    // MARK: Toolbar
    func toolbarItem(_ id:NSToolbarItem.Identifier,_ label:String,_ image:NSImage?,_ action:Selector,_ tip:String)->NSToolbarItem {
        let item=NSToolbarItem(itemIdentifier:id);item.label=label;item.paletteLabel=label;item.toolTip=tip;item.image=image;item.target=self;item.action=action;item.isBordered=true
        return item
    }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] {
        [.toggleSidebar,.sidebarTrackingSeparator,.importPhotos,.detect,.detectPending,.flexibleSpace,.rotateLeft,.rotateRight,.split,.preview,.zoom,.flexibleSpace,.flag,.claude,.accept,.space,.export,.inspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] {toolbarDefaultItemIdentifiers(toolbar)+[.space]}
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier id:NSToolbarItem.Identifier,willBeInsertedIntoToolbar flag:Bool)->NSToolbarItem? {
        switch id {
        case .importPhotos:return toolbarItem(id,"Import",symbol("photo.badge.plus","photo.on.rectangle.angled"),#selector(importImages),"Import photographs or a folder (I)")
        case .detect:return toolbarItem(id,"Detect",symbol("wand.and.stars"),#selector(detectCurrent),"Detect the cropping frame of this photograph (D)")
        case .detectPending:return toolbarItem(id,"Detect Pending",symbol("wand.and.rays","sparkles"),#selector(detectPending),"Detect every pending photograph (B)")
        case .rotateLeft:return toolbarItem(id,"Rotate Left",symbol("rotate.left"),#selector(rotateLeft),"Rotate the output counterclockwise (Shift-R)")
        case .rotateRight:return toolbarItem(id,"Rotate Right",symbol("rotate.right"),#selector(rotate),"Rotate the output clockwise (R)")
        case .split:return toolbarItem(id,"Split",symbol("rectangle.split.2x1","square.split.2x1"),#selector(proposeSplit),"Propose a split between facing pages (T)")
        case .flag:return toolbarItem(id,"Flag",symbol("flag"),#selector(toggleFlag),"Add or remove a flag (M)")
        case .claude:return toolbarItem(id,"Send to Claude",symbol("sparkles","bubble.left"),#selector(sendToClaude),"Ask Claude to check the crop of the selected pages (A)")
        case .accept:return toolbarItem(id,"Accept",symbol("checkmark.circle"),#selector(accept),"Mark reviewed and go to the next photograph (Return)")
        case .export:return toolbarItem(id,"Export",symbol("square.and.arrow.up"),#selector(exportImages),"Export a PDF or image files (E)")
        case .inspector:return toolbarItem(id,"Inspector",symbol("sidebar.right"),#selector(toggleInspector),"Show or hide the inspector")
        case .preview:
            let group=NSToolbarItemGroup(itemIdentifier:id,images:[symbol("eye") ?? NSImage()],selectionMode:.selectAny,labels:["Preview"],target:self,action:#selector(togglePreview))
            group.label="Preview";group.paletteLabel="Corrected Preview";group.toolTip="Show the corrected, adjusted result (P)";group.setSelected(canvas.preview,at:0);previewItem=group
            return group
        case .zoom:
            let images=[symbol("minus.magnifyingglass"),symbol("arrow.up.left.and.arrow.down.right","1.magnifyingglass"),symbol("plus.magnifyingglass")].map{$0 ?? NSImage()}
            let group=NSToolbarItemGroup(itemIdentifier:id,images:images,selectionMode:.momentary,labels:["Zoom Out","Fit","Zoom In"],target:self,action:#selector(zoomSegment(_:)))
            group.label="Zoom";group.paletteLabel="Zoom";group.toolTip="Zoom out, fit, zoom in (−, F, +)"
            return group
        default:return nil
        }
    }
    @objc func toggleInspector(){inspectorItem.animator().isCollapsed.toggle()}
}

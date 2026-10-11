import AppKit
import CropCore

/// The disclosure triangle of an inspector section. Whether the section is open is remembered between launches.
final class FoldButton: NSButton {
    private var body:NSView?
    private var key=""
    convenience init(key:String,open:Bool,body:NSView){
        self.init(title:"",target:nil,action:nil)
        self.key="inspectorOpen."+key;self.body=body;bezelStyle = .disclosure;setButtonType(.pushOnPushOff);target=self;action=#selector(changed)
        let remembered=UserDefaults.standard.object(forKey:self.key) as? Bool ?? open
        state=remembered ? .on:.off;body.isHidden = !remembered
    }
    /// The line under the heading, which folds away with the section.
    var rule:NSView? {didSet{rule?.isHidden=state != .on}}
    @objc func flip(){state=state == .on ? .off:.on;changed()}
    @objc func changed(){body?.isHidden=state != .on;rule?.isHidden=state != .on;UserDefaults.standard.set(state == .on,forKey:key)}
}
private final class InspectorDocument: NSView {override var isFlipped:Bool{true}}
/// The smudge brush's picture, and the same crossed out for removing smudges.
enum SmudgeIcon {
    static let brush:NSImage={let image=symbol("hand.draw","hand.point.up.left","scribble") ?? NSImage();image.isTemplate=true;return image}()
    static let erase:NSImage={
        let base=brush,size=NSSize(width:max(18,base.size.width+4),height:max(16,base.size.height+2))
        let image=NSImage(size:size,flipped:false){rect in
            base.draw(in:NSRect(x:0,y:0,width:base.size.width,height:base.size.height).offsetBy(dx:(rect.width-base.size.width)/2,dy:(rect.height-base.size.height)/2))
            // A cross from corner to corner, heavy enough to read at this size.
            let cross=NSBezierPath();cross.lineWidth=1.8;cross.lineCapStyle = .round
            let inset=rect.insetBy(dx:2.5,dy:2.5)
            cross.move(to:NSPoint(x:inset.minX,y:inset.minY));cross.line(to:NSPoint(x:inset.maxX,y:inset.maxY))
            cross.move(to:NSPoint(x:inset.minX,y:inset.maxY));cross.line(to:NSPoint(x:inset.maxX,y:inset.minY))
            NSColor.black.setStroke();cross.stroke()
            return true
        }
        image.isTemplate=true;return image
    }()
}
extension AppDelegate {
    /// A section heading. With `fold` it carries a disclosure triangle, and a click anywhere on the title folds the section too.
    func header(_ title:String,accessory:NSView?=nil,fold:FoldButton?=nil)->NSView {
        let label=NSTextField(labelWithString:title.uppercased());label.font = .systemFont(ofSize:11,weight:.semibold);label.textColor = .secondaryLabelColor
        if let fold {label.addGestureRecognizer(NSClickGestureRecognizer(target:fold,action:#selector(FoldButton.flip)))}
        let row=NSStackView(views:(fold.map{[$0]} ?? [])+[label,NSView()]+(accessory.map{[$0]} ?? []));row.spacing=4
        let line=NSBox();line.boxType = .separator;fold?.rule=line
        let stack=NSStackView(views:[row,line]);stack.orientation = .vertical;stack.spacing=4
        row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;line.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        return stack
    }
    func caption(_ text:String)->NSTextField {let label=NSTextField(labelWithString:text);label.alignment = .right;return label}
    func segments(_ labels:[String],_ action:Selector,tips:[String]=[])->NSSegmentedControl {
        let control=NSSegmentedControl(labels:labels,trackingMode:.momentary,target:self,action:action);control.segmentDistribution = .fillEqually;control.controlSize = .small;control.font = .systemFont(ofSize:11)
        for (i,tip) in tips.enumerated() {control.setToolTip(tip,forSegment:i)}
        return control
    }
    func buildInspector()->NSView {
        // The sections scroll when the window is too short for all of them.
        let root=PaneView(),scroll=NSScrollView(),document=InspectorDocument()
        scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.automaticallyAdjustsContentInsets=true;scroll.translatesAutoresizingMaskIntoConstraints=false;document.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(scroll);scroll.documentView=document
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        /// A group of controls that folds away under its heading.
        func section(_ title:String,key:String,open:Bool=true,accessory:NSView?=nil,_ views:[NSView]){
            let body=NSStackView();body.orientation = .vertical;body.alignment = .leading;body.spacing=10
            for view in views {body.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:body.widthAnchor).isActive=true}
            add(header(title,accessory:accessory,fold:FoldButton(key:key,open:open,body:body)));add(body,after:22)
        }
        func add(_ view:NSView,after gap:CGFloat?=nil){
            stack.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
            if let gap {stack.setCustomSpacing(gap,after:view)}
        }
        // Cropping frame
        detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor;detail.lineBreakMode = .byTruncatingMiddle;detail.maximumNumberOfLines=2
        note.font = .systemFont(ofSize:11);note.textColor = .labelColor;note.isSelectable=true;note.isHidden=true
        candidates.target=self;candidates.action=#selector(candidateChanged);candidates.toolTip="Proposed cropping frames ([ and ])"
        let crop=segments(["Detect","Full","Previous"],#selector(cropSegment(_:)),tips:["Detect the cropping frame (d)","Set the cropping frame to the full image (x)","Copy the previous photograph's crop (c)"])
        let corners=segments(["↖","↗","↙","↘"],#selector(cornerSegment(_:)),tips:["Select the top-left corner (1)","Select the top-right corner (2)","Select the bottom-left corner (3)","Select the bottom-right corner (4)"])
        let size=segments(["Shrink","Expand"],#selector(sizeSegment(_:)),tips:["Shrink the crop (;)","Expand the crop (')"])
        let splits=segments(["Propose","◀","▶","Remove"],#selector(splitSegment(_:)),tips:["Propose a split between facing pages (t)","Move the split left (,)","Move the split right (.)","Remove the split (Shift-T)"])
        let tilt=segments(["Auto","↺","↻","Reset"],#selector(deskewSegment(_:)),tips:["Level the lines of text (q)","Turn counterclockwise by 0.1° (Option-,)","Turn clockwise by 0.1° (Option-.)","Remove the deskew (Shift-Q)"])
        let pictures=segments(["Add Zone","Clear"],#selector(zoneSegment(_:)),tips:["Draw a picture zone that keeps its gray tones on a black-and-white page (w)","Remove the picture zones (Shift-W)"])
        // Two buttons: the brush, lit while it is in hand, and the same picture crossed out to remove the smudges.
        smudgeButton.image=SmudgeIcon.brush;smudgeButton.setButtonType(.pushOnPushOff);smudgeButton.bezelStyle = .rounded;smudgeButton.controlSize = .small;smudgeButton.imagePosition = .imageOnly
        smudgeButton.target=self;smudgeButton.action=#selector(toggleSmudge);smudgeButton.toolTip="Pick up or put down the smudge brush, which blurs print so it cannot be read (Shift-B)"
        clearSmudgeButton.image=SmudgeIcon.erase;clearSmudgeButton.bezelStyle = .rounded;clearSmudgeButton.controlSize = .small;clearSmudgeButton.imagePosition = .imageOnly
        clearSmudgeButton.target=self;clearSmudgeButton.action=#selector(removeSmudges);clearSmudgeButton.toolTip="Remove the smudges (Option-Shift-B)"
        for button in [smudgeButton,clearSmudgeButton] {button.widthAnchor.constraint(equalToConstant:44).isActive=true}
        let smudgeButtons=NSStackView(views:[smudgeButton,clearSmudgeButton,NSView()]);smudgeButtons.spacing=8
        if let size=UserDefaults.standard.object(forKey:"smudgeSize") as? Double {smudgeSizeSlider.doubleValue=size}
        if let strength=UserDefaults.standard.object(forKey:"smudgeStrength") as? Double {smudgeStrengthSlider.doubleValue=strength}
        for slider in [smudgeSizeSlider,smudgeStrengthSlider] {slider.isContinuous=true;slider.target=self;slider.action=#selector(smudgeBrushChanged(_:));slider.controlSize = .small}
        for value in [smudgeSizeValue,smudgeStrengthValue] {value.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);value.textColor = .secondaryLabelColor;value.alignment = .right;value.widthAnchor.constraint(equalToConstant:26).isActive=true}
        smudgeSizeSlider.toolTip="Width of the smudge brush";smudgeStrengthSlider.toolTip="How heavily the next strokes blur the print"
        let brushSize=NSStackView(views:[smudgeSizeSlider,smudgeSizeValue]),brushStrength=NSStackView(views:[smudgeStrengthSlider,smudgeStrengthValue])
        smudgeBrushChanged(nil)
        let frame=NSGridView(views:[[caption("Proposal:"),candidates],[caption("Frame:"),crop],[caption("Corner:"),corners],[caption("Size:"),size],[caption("Split:"),splits],[caption("Deskew:"),tilt],[caption("Pictures:"),pictures],[caption("Smudge:"),smudgeButtons],[caption("Brush:"),brushSize],[caption("Strength:"),brushStrength]])
        // The brush's width and strength show only while it is in hand.
        smudgeRows=[frame.row(at:frame.numberOfRows-2),frame.row(at:frame.numberOfRows-1)];showSmudgeState()
        frame.rowSpacing=7;frame.columnSpacing=8;frame.column(at:0).xPlacement = .trailing;frame.column(at:0).width=78;frame.column(at:1).xPlacement = .fill
        section("Cropping Frame",key:"crop",[detail,note,frame])
        // Image settings
        let reset=NSButton(image:symbol("arrow.counterclockwise") ?? NSImage(),target:self,action:#selector(resetAdjustments));reset.isBordered=false;reset.toolTip="Reset image settings"
        cleanupControl.segmentCount=4;cleanupControl.trackingMode = .selectOne;cleanupControl.segmentDistribution = .fillEqually;cleanupControl.target=self;cleanupControl.action=#selector(adjustmentChanged(_:))
        let icons=[symbol("xmark"),symbol("circle.lefthalf.filled"),symbol("circle.hexagongrid","circle.dotted"),symbol("paintpalette")]
        for (i,mode) in Cleanup.allCases.enumerated() {
            if let icon=icons[i] {cleanupControl.setImage(icon,forSegment:i)} else {cleanupControl.setLabel(mode.title,forSegment:i)}
            cleanupControl.setToolTip(mode == .none ? "No cleanup":"\(mode.title): even out lighting and whiten the paper",forSegment:i)
        }
        cleanupControl.selectedSegment=0
        despeckleControl.segmentCount=4;despeckleControl.trackingMode = .selectOne;despeckleControl.segmentDistribution = .fillEqually;despeckleControl.controlSize = .small;despeckleControl.target=self;despeckleControl.action=#selector(adjustmentChanged(_:))
        for (i,name) in ["Off","1","2","3"].enumerated() {despeckleControl.setLabel(name,forSegment:i);despeckleControl.setToolTip(["No speck removal","Cautious: only the smallest specks","Normal","Aggressive: larger specks too"][i]+" (Black & White only)",forSegment:i)}
        despeckleControl.selectedSegment=0
        cleanupName.font = .systemFont(ofSize:11);cleanupName.textColor = .secondaryLabelColor;cleanupName.alignment = .center
        for slider in [exposureSlider,brightnessSlider,contrastSlider,sharpnessSlider] {slider.isContinuous=true;slider.target=self;slider.action=#selector(adjustmentChanged(_:));slider.controlSize = .small}
        // A tick marks the neutral middle of brightness and contrast.
        for slider in [exposureSlider,brightnessSlider,contrastSlider] {slider.numberOfTickMarks=3}
        exposureSlider.toolTip="Lighten or darken the photograph as a longer or shorter exposure would, up to two stops either way"
        for value in [exposureValue,brightnessValue,contrastValue,sharpnessValue] {value.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);value.textColor = .secondaryLabelColor;value.alignment = .right}
        let blank=NSGridCell.emptyContentView
        let adjustments=NSGridView(views:[[caption("Mode:"),cleanupControl,blank],[blank,cleanupName,blank],[caption("Despeckle:"),despeckleControl,blank],[caption("Exposure:"),exposureSlider,exposureValue],[caption("Brightness:"),brightnessSlider,brightnessValue],[caption("Contrast:"),contrastSlider,contrastValue],[caption("Sharpness:"),sharpnessSlider,sharpnessValue]])
        for row in 0..<3 {adjustments.mergeCells(inHorizontalRange:NSRange(location:1,length:2),verticalRange:NSRange(location:row,length:1));adjustments.cell(atColumnIndex:1,rowIndex:row).xPlacement = .fill}
        adjustments.column(at:2).width=30
        adjustments.rowSpacing=6;adjustments.columnSpacing=8;adjustments.column(at:0).xPlacement = .trailing;adjustments.column(at:0).width=78;adjustments.row(at:1).topPadding = -4
        section("Image Settings",key:"adjustments",accessory:reset,[adjustments])
        // Page format
        func field(_ f:NSTextField)->NSView {
            f.alignment = .left;f.target=self;f.action=#selector(formatChanged(_:));f.cell?.sendsActionOnEndEditing=true;f.widthAnchor.constraint(equalToConstant:64).isActive=true
            let row=NSStackView(views:[f,NSTextField(labelWithString:"cm")]);row.spacing=6;return row
        }
        fitPopup.addItems(withTitles:["None"]+PaperSize.allCases.map{$0.title});fitPopup.target=self;fitPopup.action=#selector(formatChanged(_:))
        widthField.toolTip="Physical width of the corrected page. The height follows the crop's proportions.";heightField.toolTip=widthField.toolTip
        fitPopup.toolTip="Centre the page on a standard sheet in exported PDFs"
        let format=NSGridView(views:[[caption("Width:"),field(widthField)],[caption("Height:"),field(heightField)],[caption("Presets:"),fitPopup]])
        format.rowSpacing=6;format.columnSpacing=8;format.column(at:0).xPlacement = .trailing;format.column(at:0).width=78;format.column(at:1).xPlacement = .leading
        resolutionLabel.font = .systemFont(ofSize:11);resolutionLabel.textColor = .secondaryLabelColor;resolutionLabel.alignment = .center
        let all=applyAllButton;all.target=self;all.action=#selector(applySettingsToAll);all.bezelStyle = .rounded;all.controlSize = .small;all.toolTip="Copy this page's image settings (cleanup, exposure, brightness, contrast, sharpness) and page format to every page. Crops and splits are left as they are."
        section("Page Format",key:"format",open:false,[format,resolutionLabel])
        // Outside the sections, because it carries the image settings as well as the page format.
        add(all,after:22)
        // The keys used most, kept in view; the full list is one key away.
        let keys:[(String,String)]=[("← / →","Previous / next image"),("C","Set crop to same as previous image"),("V","Copy image settings from previous image"),("T","Propose split"),("R","Rotate (Shift-R for reverse)"),("; / '","Decrease / increase current crop"),("H J K L","Increase crop edges (Shift to decrease, Option to move crop)"),("/","See more shortcuts")]
        let shortcuts=NSGridView(views:keys.map{entry->[NSView] in
            let key=NSTextField(labelWithString:ShortcutReference.shown(entry.0));key.font = .monospacedSystemFont(ofSize:11,weight:.medium);key.textColor = .secondaryLabelColor;key.alignment = .right
            let action=NSTextField(wrappingLabelWithString:entry.1);action.font = .systemFont(ofSize:11);action.textColor = .secondaryLabelColor
            action.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            return [key,action]
        })
        shortcuts.rowSpacing=4;shortcuts.columnSpacing=8;shortcuts.column(at:0).xPlacement = .trailing;shortcuts.column(at:0).width=58;shortcuts.rowAlignment = .firstBaseline
        section("Shortcuts",key:"shortcuts",[shortcuts])
        inspectorControls=[candidates,crop,corners,size,splits,tilt,pictures,reset,smudgeButton,smudgeSizeSlider,smudgeStrengthSlider,cleanupControl,exposureSlider,brightnessSlider,contrastSlider,sharpnessSlider,widthField,heightField,fitPopup,all]
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo:root.topAnchor),scroll.bottomAnchor.constraint(equalTo:root.bottomAnchor),scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),
            document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo:document.topAnchor,constant:14),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-16),
            stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-12)])
        return root
    }
}

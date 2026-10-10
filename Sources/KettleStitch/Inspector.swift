import AppKit
import CropCore

extension AppDelegate {
    func header(_ title:String,accessory:NSView?=nil)->NSView {
        let label=NSTextField(labelWithString:title.uppercased());label.font = .systemFont(ofSize:11,weight:.semibold);label.textColor = .secondaryLabelColor
        let row=NSStackView(views:[label,NSView()]+(accessory.map{[$0]} ?? []))
        let line=NSBox();line.boxType = .separator
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
        let root=PaneView()
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
        func add(_ view:NSView,after gap:CGFloat?=nil){
            stack.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
            if let gap {stack.setCustomSpacing(gap,after:view)}
        }
        // Cropping frame
        detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor;detail.lineBreakMode = .byTruncatingMiddle;detail.maximumNumberOfLines=2
        note.font = .systemFont(ofSize:11);note.textColor = .labelColor;note.isSelectable=true;note.isHidden=true
        candidates.target=self;candidates.action=#selector(candidateChanged);candidates.toolTip="Proposed cropping frames ([ and ])"
        let crop=segments(["Detect","Full","Previous"],#selector(cropSegment(_:)),tips:["Detect the cropping frame (D)","Set the cropping frame to the full image (X)","Copy the previous photograph's crop (C)"])
        let corners=segments(["↖","↗","↙","↘"],#selector(cornerSegment(_:)),tips:["Select the top-left corner (1)","Select the top-right corner (2)","Select the bottom-left corner (3)","Select the bottom-right corner (4)"])
        let size=segments(["Shrink","Expand"],#selector(sizeSegment(_:)),tips:["Shrink the crop (;)","Expand the crop (')"])
        let splits=segments(["Propose","◀","▶","Remove"],#selector(splitSegment(_:)),tips:["Propose a split between facing pages (T)","Move the split left (,)","Move the split right (.)","Remove the split (Shift-T)"])
        let tilt=segments(["Auto","↺","↻","Reset"],#selector(deskewSegment(_:)),tips:["Level the lines of text (Q)","Turn counterclockwise by 0.1° (Option-,)","Turn clockwise by 0.1° (Option-.)","Remove the deskew (Shift-Q)"])
        let pictures=segments(["Add Zone","Clear"],#selector(zoneSegment(_:)),tips:["Draw a picture zone that keeps its gray tones on a black-and-white page (W)","Remove the picture zones (Shift-W)"])
        smudgeControl.segmentCount=2;smudgeControl.trackingMode = .selectAny;smudgeControl.segmentDistribution = .fillEqually;smudgeControl.target=self;smudgeControl.action=#selector(smudgeSegment(_:))
        smudgeControl.setLabel("Paint",forSegment:0);smudgeControl.setLabel("Clear",forSegment:1)
        smudgeControl.setToolTip("Pick up or put down the smudge brush, which blurs print so it cannot be read (Shift-B)",forSegment:0);smudgeControl.setToolTip("Remove the smudges (Option-Shift-B)",forSegment:1)
        if let size=UserDefaults.standard.object(forKey:"smudgeSize") as? Double {smudgeSizeSlider.doubleValue=size}
        if let strength=UserDefaults.standard.object(forKey:"smudgeStrength") as? Double {smudgeStrengthSlider.doubleValue=strength}
        for slider in [smudgeSizeSlider,smudgeStrengthSlider] {slider.isContinuous=true;slider.target=self;slider.action=#selector(smudgeBrushChanged(_:));slider.controlSize = .small}
        for value in [smudgeSizeValue,smudgeStrengthValue] {value.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);value.textColor = .secondaryLabelColor;value.alignment = .right;value.widthAnchor.constraint(equalToConstant:26).isActive=true}
        smudgeSizeSlider.toolTip="Width of the smudge brush";smudgeStrengthSlider.toolTip="How heavily the next strokes blur the print"
        let brushSize=NSStackView(views:[smudgeSizeSlider,smudgeSizeValue]),brushStrength=NSStackView(views:[smudgeStrengthSlider,smudgeStrengthValue])
        smudgeBrushChanged(nil)
        let frame=NSGridView(views:[[caption("Proposal:"),candidates],[caption("Frame:"),crop],[caption("Corner:"),corners],[caption("Size:"),size],[caption("Split:"),splits],[caption("Deskew:"),tilt],[caption("Pictures:"),pictures],[caption("Smudge:"),smudgeControl],[caption("Brush:"),brushSize],[caption("Strength:"),brushStrength]])
        frame.rowSpacing=7;frame.columnSpacing=8;frame.column(at:0).xPlacement = .trailing;frame.column(at:0).width=78;frame.column(at:1).xPlacement = .fill
        add(header("Cropping Frame"));add(detail);add(note);add(frame,after:22)
        // Image adjustments
        let reset=NSButton(image:symbol("arrow.counterclockwise") ?? NSImage(),target:self,action:#selector(resetAdjustments));reset.isBordered=false;reset.toolTip="Reset image adjustments"
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
        for slider in [brightnessSlider,contrastSlider,sharpnessSlider] {slider.isContinuous=true;slider.target=self;slider.action=#selector(adjustmentChanged(_:));slider.controlSize = .small}
        // A tick marks the neutral middle of brightness and contrast.
        for slider in [brightnessSlider,contrastSlider] {slider.numberOfTickMarks=3}
        for value in [brightnessValue,contrastValue,sharpnessValue] {value.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);value.textColor = .secondaryLabelColor;value.alignment = .right}
        let blank=NSGridCell.emptyContentView
        let adjustments=NSGridView(views:[[caption("Cleanup:"),cleanupControl,blank],[blank,cleanupName,blank],[caption("Despeckle:"),despeckleControl,blank],[caption("Brightness:"),brightnessSlider,brightnessValue],[caption("Contrast:"),contrastSlider,contrastValue],[caption("Sharpness:"),sharpnessSlider,sharpnessValue]])
        for row in 0..<3 {adjustments.mergeCells(inHorizontalRange:NSRange(location:1,length:2),verticalRange:NSRange(location:row,length:1));adjustments.cell(atColumnIndex:1,rowIndex:row).xPlacement = .fill}
        adjustments.column(at:2).width=30
        adjustments.rowSpacing=6;adjustments.columnSpacing=8;adjustments.column(at:0).xPlacement = .trailing;adjustments.column(at:0).width=78;adjustments.row(at:1).topPadding = -4
        add(header("Image Adjustments",accessory:reset));add(adjustments,after:22)
        // Page format
        func field(_ f:NSTextField)->NSView {
            f.alignment = .left;f.target=self;f.action=#selector(formatChanged(_:));f.cell?.sendsActionOnEndEditing=true;f.widthAnchor.constraint(equalToConstant:64).isActive=true
            let row=NSStackView(views:[f,NSTextField(labelWithString:"cm")]);row.spacing=6;return row
        }
        fitPopup.addItems(withTitles:["None"]+PaperSize.allCases.map{$0.title});fitPopup.target=self;fitPopup.action=#selector(formatChanged(_:))
        widthField.toolTip="Physical width of the corrected page. The height follows the crop's proportions.";heightField.toolTip=widthField.toolTip
        fitPopup.toolTip="Centre the page on a standard sheet in exported PDFs"
        let format=NSGridView(views:[[caption("Width:"),field(widthField)],[caption("Height:"),field(heightField)],[caption("Fit into:"),fitPopup]])
        format.rowSpacing=6;format.columnSpacing=8;format.column(at:0).xPlacement = .trailing;format.column(at:0).width=78;format.column(at:1).xPlacement = .leading
        resolutionLabel.font = .systemFont(ofSize:11);resolutionLabel.textColor = .secondaryLabelColor;resolutionLabel.alignment = .center
        let all=NSButton(title:"Apply Settings to All Pages",target:self,action:#selector(applySettingsToAll));all.bezelStyle = .rounded;all.controlSize = .small;all.toolTip="Copy this page's image adjustments and page format to every page"
        add(header("Page Format"));add(format);add(resolutionLabel);add(all)
        inspectorControls=[candidates,crop,corners,size,splits,tilt,pictures,reset,smudgeControl,smudgeSizeSlider,smudgeStrengthSlider,cleanupControl,brightnessSlider,contrastSlider,sharpnessSlider,widthField,heightField,fitPopup,all]
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:root.safeAreaLayoutGuide.topAnchor,constant:14),stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:root.bottomAnchor,constant:-12)])
        return root
    }
}

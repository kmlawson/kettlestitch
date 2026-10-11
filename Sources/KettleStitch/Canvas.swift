import AppKit
import CropCore

final class CropCanvas: NSView {
    private(set) var edgeFlashes=0
    /// A brief red frame around the canvas: the first or last photograph has been reached.
    func flashEdges(){
        edgeFlashes+=1;wantsLayer=true
        let frame=CALayer();frame.frame=visibleRect;frame.borderColor=NSColor.systemRed.cgColor;frame.borderWidth=6;frame.opacity=0
        layer?.addSublayer(frame)
        let fade=CABasicAnimation(keyPath:"opacity");fade.fromValue=1;fade.toValue=0;fade.duration=0.5
        CATransaction.begin();CATransaction.setCompletionBlock{frame.removeFromSuperlayer()};frame.add(fade,forKey:nil);CATransaction.commit()
    }
    static let emptyProjectMessage="Drop photographs or a folder here\nor choose File ▸ Import Photographs.\n\nYour originals stay untouched."
    var placeholder=CropCanvas.emptyProjectMessage {didSet{needsDisplay=true}}
    /// The picture on the canvas: the photograph, or after `showOutput` the corrected output.
    var image: CGImage? {didSet {if !settingOutput {outputShown=false};needsDisplay=true}}
    private var settingOutput=false
    /// True while the picture is the corrected output, which is already turned; false for the photograph.
    private(set) var outputShown=false
    func showOutput(_ output: CGImage){settingOutput=true;image=output;settingOutput=false;outputShown=true}
    var quad=Quad.full {didSet{needsDisplay=true}}
    var preview=false {didSet{needsDisplay=true}}
    /// The proposed division between facing pages, and the output rotation it is measured in.
    var split: PageSplit? {didSet{needsDisplay=true}}
    var rotation=0 {didSet{needsDisplay=true}}
    var onSplitCommit: ((PageSplit)->Void)?
    /// Picture zones of the page, and the one being drawn while `zoneMode` is on.
    var zones: [PictureZone]=[] {didSet{needsDisplay=true}}
    var zoneMode=false {didSet{needsDisplay=true;window?.invalidateCursorRects(for:self)}}
    var onZoneCommit: ((PictureZone)->Void)?
    var onZoneRemove: ((Int)->Void)?
    static let zoneColor=NSColor.systemBlue
    /// While on, a drag paints a smudge stroke instead of moving the crop. It stays on until switched off.
    var smudgeMode=false {didSet{smudgeDraft=[];needsDisplay=true;window?.invalidateCursorRects(for:self)}}
    /// Half the brush's width, as a fraction of the photograph's longer side.
    var smudgeRadius=0.02
    var onSmudgeCommit: (([Point])->Void)?
    private var smudgeDraft: [Point]=[]
    /// While on, Option-click picks the place to copy from and a drag paints a copy of it. The brush's width is
    /// `smudgeRadius`, shared with the smudge brush.
    var cloneMode=false {didSet{cloneDraft=[];needsDisplay=true;window?.invalidateCursorRects(for:self)}}
    /// The place to copy from, on the photograph, and how far it lies from where painting began. The distance is
    /// fixed by the first stroke after a source is chosen and kept for the strokes that follow.
    private(set) var cloneSource: Point?
    private(set) var cloneOffset: Point?
    var onCloneCommit: (([Point],Point)->Void)?
    /// Called with true when a source has just been chosen, false when a drag began with none.
    var onCloneSource: ((Bool)->Void)?
    private var cloneDraft: [Point]=[]
    static let cloneColor=NSColor.systemTeal
    func forgetCloneSource(){cloneSource=nil;cloneOffset=nil;needsDisplay=true}
    private var zoneStart: (Double,Double)?
    private var zoneDraft: PictureZone?
    static let splitColor=NSColor.systemPink
    private enum SplitGrip {case top,bottom,line}
    private var splitGrip: SplitGrip?
    private var splitBefore: PageSplit?
    private var splitStart=0.0
    var isDraggingSplit: Bool {splitGrip != nil}
    var zoom: CGFloat=1 {didSet{needsDisplay=true}}
    var pan=CGPoint.zero
    var onCommit: ((Quad)->Void)?
    var onNavigate: ((Int)->Void)?
    var onAccept: (()->Void)?
    var onUndo: (()->Void)?
    private var corner: Int?
    private var edge: Int?
    private var showMagnifier=false
    private var magnifierOpposite=false
    private(set) var keyboardSelection=false
    var isMagnifierVisible: Bool {showMagnifier && corner != nil && !preview}
    private var before=Quad.full
    private var start=CGPoint.zero
    private var oldPan=CGPoint.zero
    private var moving=false
    /// True while the space bar is down: a drag then moves the picture in the window, whatever is under the pointer.
    var spaceHeld=false {didSet{if spaceHeld != oldValue {window?.invalidateCursorRects(for:self)}}}
    private var panning=false
    private var spaceMonitor: Any?
    /// True while a drag begun inside the crop is moving the crop.
    var isMovingCrop: Bool {moving}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let spaceMonitor {NSEvent.removeMonitor(spaceMonitor)};spaceMonitor=nil
        guard window != nil else {return}
        // The space bar is watched wherever the keyboard is in this window, except while text is being typed.
        spaceMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]){[weak self] event in
            guard let self,event.keyCode==49,event.window===self.window,event.modifierFlags.isDisjoint(with:[.command,.control]) else {return event}
            if event.type == .keyUp {self.spaceHeld=false;return event}
            guard !(self.window?.firstResponder is NSText) else {return event}
            self.spaceHeld=true;return nil
        }
    }
    override var isFlipped: Bool {true}
    override var acceptsFirstResponder: Bool {true}
    /// How the photograph is turned on screen: by the page's output rotation, so the crop is adjusted the way round
    /// it will come out. The corrected output is already turned; the photograph standing in while a preview is
    /// being made is turned like any other.
    var turn: ViewTurn {ViewTurn(outputShown ? 0:rotation)}
    /// The picture's size as it is shown, in its own pixels.
    private var shownSize: CGSize {
        guard let image else {return .zero}
        return turn.sideways ? CGSize(width:image.height,height:image.width):CGSize(width:image.width,height:image.height)
    }
    var imageRect: CGRect {
        guard image != nil else {return .zero}
        let shown=shownSize,scale=min((bounds.width-64)/shown.width,(bounds.height-64)/shown.height)*zoom
        let size=CGSize(width:shown.width*scale,height:shown.height*scale)
        return CGRect(x:(bounds.width-size.width)/2+pan.x,y:(bounds.height-size.height)/2+pan.y,width:size.width,height:size.height)
    }
    /// Where a point of the photograph is on screen, and the point of the photograph at a place on screen.
    func position(_ p: Point) -> CGPoint {let r=imageRect,s=turn.shown(p);return CGPoint(x:r.minX+s.x*r.width,y:r.minY+s.y*r.height)}
    func normalized(_ p: CGPoint) -> Point {let r=imageRect;return turn.photograph(Point(min(1,max(0,(p.x-r.minX)/r.width)),min(1,max(0,(p.y-r.minY)/r.height))))}
    /// Draws the picture into `rect`, which has the shape it is shown in, turned as it is shown.
    private func drawPicture(_ image: CGImage, in rect: CGRect) {
        let picture=NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
        guard turn.quarterTurns != 0 else {picture.draw(in:rect);return}
        NSGraphicsContext.saveGraphicsState()
        let around=NSAffineTransform();around.translateX(by:rect.midX,yBy:rect.midY);around.rotate(byDegrees:CGFloat(turn.quarterTurns)*90);around.concat()
        let w=turn.sideways ? rect.height:rect.width,h=turn.sideways ? rect.width:rect.height
        picture.draw(in:CGRect(x:-w/2,y:-h/2,width:w,height:h))
        NSGraphicsContext.restoreGraphicsState()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite:0.105,alpha:1).setFill();bounds.fill()
        guard let image else {
            let s=placeholder
            let centred=NSMutableParagraphStyle();centred.alignment = .center
            let attrs: [NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.lightGray,.paragraphStyle:centred]
            (s as NSString).draw(in:CGRect(x:40,y:bounds.midY-50,width:max(0,bounds.width-80),height:120),withAttributes:attrs);return
        }
        drawPicture(image,in:imageRect)
        if preview {
            // The corrected output is shown, so the split is simply a line across it.
            // A split spread is shown as its two pages, so there is no single output to draw zones over.
            if split==nil {let r=imageRect;for zone in zones {drawZone([CGPoint(x:r.minX+zone.minU*r.width,y:r.minY+zone.minV*r.height),CGPoint(x:r.minX+zone.maxU*r.width,y:r.minY+zone.minV*r.height),CGPoint(x:r.minX+zone.maxU*r.width,y:r.minY+zone.maxV*r.height),CGPoint(x:r.minX+zone.minU*r.width,y:r.minY+zone.maxV*r.height)],draft:false)}}
            return
        }
        let path=NSBezierPath();path.move(to:position(quad.points[0]));for p in quad.points.dropFirst(){path.line(to:position(p))};path.close()
        let shade=NSBezierPath(rect:imageRect);shade.append(path);shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.52).setFill();shade.fill()
        NSColor.systemMint.setStroke();path.lineWidth=2;path.stroke()
        for (i,p) in quad.points.enumerated() {
            let pos=position(p),r=CGRect(x:pos.x-6,y:pos.y-6,width:12,height:12)
            NSColor.white.setFill();NSBezierPath(ovalIn:r).fill()
            if i==corner {NSColor.systemMint.setStroke();let ring=NSBezierPath(ovalIn:r.insetBy(dx:-4,dy:-4));ring.lineWidth=2;ring.stroke()}
        }
        for zone in zones+(zoneDraft.map{[$0]} ?? []) {if let outline=zone.outline(quad:quad,rotation:rotation) {drawZone(outline.map(position),draft:zone==zoneDraft)}}
        if let ends=splitEnds {drawSplit(from:ends.0,to:ends.1,handles:true)}
        if let first=smudgeDraft.first {
            // The stroke at its true width, until the blur itself has been rendered.
            let r=imageRect,stroke=NSBezierPath();stroke.lineCapStyle = .round;stroke.lineJoinStyle = .round;stroke.lineWidth=max(2,2*smudgeRadius*max(r.width,r.height))
            stroke.move(to:position(first));stroke.line(to:position(first));for p in smudgeDraft.dropFirst() {stroke.line(to:position(p))}
            NSColor.systemPink.withAlphaComponent(0.45).setStroke();stroke.stroke()
        }
        if cloneMode {
            let r=imageRect,width=max(2,2*smudgeRadius*max(r.width,r.height))
            if let first=cloneDraft.first {
                let stroke=NSBezierPath();stroke.lineCapStyle = .round;stroke.lineJoinStyle = .round;stroke.lineWidth=width
                stroke.move(to:position(first));stroke.line(to:position(first));for p in cloneDraft.dropFirst() {stroke.line(to:position(p))}
                CropCanvas.cloneColor.withAlphaComponent(0.4).setStroke();stroke.stroke()
            }
            // A ring where the copy is taken from: the chosen source, or while painting the place under the brush's twin.
            var from=cloneSource
            if let last=cloneDraft.last,let offset=cloneOffset {from=Point(last.x+offset.x,last.y+offset.y)}
            if let from {
                let at=position(from),ring=NSBezierPath(ovalIn:CGRect(x:at.x-width/2,y:at.y-width/2,width:width,height:width))
                NSColor.black.withAlphaComponent(0.5).setStroke();ring.lineWidth=3;ring.stroke()
                CropCanvas.cloneColor.setStroke();ring.lineWidth=1.5;ring.stroke()
                let cross=NSBezierPath();cross.move(to:CGPoint(x:at.x-5,y:at.y));cross.line(to:CGPoint(x:at.x+5,y:at.y));cross.move(to:CGPoint(x:at.x,y:at.y-5));cross.line(to:CGPoint(x:at.x,y:at.y+5));cross.stroke()
            }
        }
        if let edge {
            NSColor.white.setStroke();let selected=NSBezierPath()
            selected.move(to:position(quad.points[edge]));selected.line(to:position(quad.points[(edge+1)%4]));selected.lineWidth=3;selected.stroke()
        }
        if let corner, showMagnifier {
            // A clipped, enlarged source patch with a fixed crosshair for precise placement.
            let p=quad.points[corner],pos=position(p)
            let defaultBox=CGRect(x:bounds.width-190,y:20,width:164,height:164)
            let oppositeBox=CGRect(x:26,y:bounds.height-184,width:164,height:164)
            let currentBox=magnifierOpposite ? oppositeBox:defaultBox
            // Keep the handle and nearby pointer clear; retain placement to avoid flicker.
            if currentBox.insetBy(dx:-24,dy:-24).contains(pos) {magnifierOpposite.toggle()}
            let box=magnifierOpposite ? oppositeBox:defaultBox
            NSGraphicsContext.saveGraphicsState();NSBezierPath(roundedRect:box,xRadius:10,yRadius:10).addClip()
            let r=imageRect,scale:CGFloat=3
            let dest=CGRect(x:box.midX+(r.minX-pos.x)*scale,y:box.midY+(r.minY-pos.y)*scale,width:r.width*scale,height:r.height*scale)
            NSColor.black.setFill();box.fill();drawPicture(image,in:dest)
            NSColor.systemMint.setStroke();let cross=NSBezierPath();cross.move(to:CGPoint(x:box.midX-12,y:box.midY));cross.line(to:CGPoint(x:box.midX+12,y:box.midY));cross.move(to:CGPoint(x:box.midX,y:box.midY-12));cross.line(to:CGPoint(x:box.midX,y:box.midY+12));cross.stroke();NSGraphicsContext.restoreGraphicsState()
        }
    }
    func drawZone(_ corners:[CGPoint],draft:Bool){
        let path=NSBezierPath();path.move(to:corners[0]);for p in corners.dropFirst(){path.line(to:p)};path.close()
        CropCanvas.zoneColor.withAlphaComponent(draft ? 0.25:0.14).setFill();path.fill()
        CropCanvas.zoneColor.setStroke();path.lineWidth=1.5;path.setLineDash([6,4],count:2,phase:0);path.stroke()
    }
    private func outputPosition(_ p:CGPoint)->(Double,Double)? {SplitGeometry.position(of:normalized(p),quad:quad,rotation:rotation).map{($0.u,$0.v)}}
    /// The index of the picture zone under a point in the view, topmost first.
    func zone(at p:CGPoint)->Int? {
        guard !preview,let (u,v)=outputPosition(p) else{return nil}
        return zones.indices.reversed().first{zones[$0].contains(u,v)}
    }
    override func rightMouseDown(with event:NSEvent){
        if let index=zone(at:convert(event.locationInWindow,from:nil)) {onZoneRemove?(index)} else {super.rightMouseDown(with:event)}
    }
    override func resetCursorRects(){if spaceHeld {addCursorRect(bounds,cursor:.openHand)} else if zoneMode || smudgeMode || cloneMode {addCursorRect(bounds,cursor:.crosshair)}}
    /// True when a point of the view lies within the cropping frame.
    func cropContains(_ point: CGPoint) -> Bool {
        let outline=NSBezierPath();outline.move(to:position(quad.points[0]));for p in quad.points.dropFirst() {outline.line(to:position(p))};outline.close()
        return outline.contains(point)
    }
    /// The split's two ends in view coordinates while the photograph is shown.
    var splitEnds: (CGPoint,CGPoint)? {
        guard image != nil,let split,let line=SplitGeometry.line(split,quad:quad,rotation:rotation) else{return nil}
        return (position(line.0),position(line.1))
    }
    func drawSplit(from a:CGPoint,to b:CGPoint,handles:Bool){
        let line=NSBezierPath();line.move(to:a);line.line(to:b);line.lineWidth=splitGrip == nil ? 2:3
        NSColor.black.withAlphaComponent(0.35).setStroke();let shadow=line.copy() as! NSBezierPath;shadow.lineWidth=line.lineWidth+2;shadow.stroke()
        CropCanvas.splitColor.setStroke();line.stroke()
        guard handles else{return}
        for p in [a,b] {let r=CGRect(x:p.x-5,y:p.y-5,width:10,height:10);CropCanvas.splitColor.setFill();NSBezierPath(rect:r).fill();NSColor.white.setStroke();NSBezierPath(rect:r).stroke()}
    }
    /// Which part of the split, if any, a click at `p` takes hold of: an end moves alone, the line moves whole.
    private func splitGrip(at p:CGPoint)->SplitGrip? {
        guard let (a,b)=splitEnds else{return nil}
        if hypot(p.x-a.x,p.y-a.y)<=14 {return .top}
        if hypot(p.x-b.x,p.y-b.y)<=14 {return .bottom}
        let dx=b.x-a.x,dy=b.y-a.y,len=dx*dx+dy*dy
        guard len>0 else{return nil}
        let t=min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/len))
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)<=8 ? .line:nil
    }
    private func across(_ p:CGPoint)->Double? {SplitGeometry.position(of:normalized(p),quad:quad,rotation:rotation)?.u}
    override func mouseDown(with event: NSEvent) {
        keyboardSelection=false;window?.makeFirstResponder(self);start=convert(event.locationInWindow,from:nil);oldPan=pan;before=quad;showMagnifier=false;magnifierOpposite=false;edge=nil;corner=nil;splitGrip=nil;splitBefore=split;moving=false
        // With the space bar down a drag moves the picture, in any mode.
        panning=spaceHeld
        guard !preview,!panning else {return}
        if zoneMode {zoneStart=outputPosition(start);zoneDraft=nil;return}
        if smudgeMode {if image != nil,imageRect.contains(start) {smudgeDraft=[normalized(start)];needsDisplay=true};return}
        if cloneMode {
            guard image != nil,imageRect.contains(start) else {return}
            if event.modifierFlags.contains(.option) {cloneSource=normalized(start);cloneOffset=nil;needsDisplay=true;onCloneSource?(true);return}
            guard let source=cloneSource else {onCloneSource?(false);return}
            let first=normalized(start)
            if cloneOffset == nil {cloneOffset=Point(source.x-first.x,source.y-first.y)}
            cloneDraft=[first];needsDisplay=true;return
        }
        corner=(0..<4).min{hypot(position(quad.points[$0]).x-start.x,position(quad.points[$0]).y-start.y)<hypot(position(quad.points[$1]).x-start.x,position(quad.points[$1]).y-start.y)}
        if let c=corner, hypot(position(quad.points[c]).x-start.x,position(quad.points[c]).y-start.y)>24 {corner=nil}
        moving=event.modifierFlags.contains(.option)
        if moving {corner=nil}
        else if corner==nil,let grip=splitGrip(at:start) {splitGrip=grip;splitStart=across(start) ?? 0.5}
        else if corner==nil {
            func distanceToEdge(_ i:Int)->CGFloat {
                let a=position(quad.points[i]),b=position(quad.points[(i+1)%4])
                let dx=b.x-a.x,dy=b.y-a.y,len=dx*dx+dy*dy
                guard len>0 else{return .infinity}
                let t=min(1,max(0,((start.x-a.x)*dx+(start.y-a.y)*dy)/len))
                return hypot(start.x-a.x-t*dx,start.y-a.y-t*dy)
            }
            if let nearest=(0..<4).min(by:{distanceToEdge($0)<distanceToEdge($1)}),distanceToEdge(nearest)<=10 {edge=nearest}
            // Inside the crop, away from its corners, edges and split line, a drag moves the crop.
            else if image != nil,cropContains(start) {moving=true}
        }
        showMagnifier=corner != nil;needsDisplay=true
    }
    override func mouseDragged(with event: NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if panning {pan=CGPoint(x:oldPan.x+p.x-start.x,y:oldPan.y+p.y-start.y);needsDisplay=true;return}
        if zoneMode,!preview {if let a=zoneStart,let b=outputPosition(p){zoneDraft=PictureZone(from:a,to:b);needsDisplay=true};return}
        if smudgeMode,!preview {
            // Points closer together than a few pixels add nothing to the stroke.
            if let last=smudgeDraft.last.map(position),hypot(p.x-last.x,p.y-last.y)>=3 {smudgeDraft.append(normalized(p));needsDisplay=true}
            return
        }
        if cloneMode,!preview {
            if let last=cloneDraft.last.map(position),hypot(p.x-last.x,p.y-last.y)>=3 {cloneDraft.append(normalized(p));needsDisplay=true}
            return
        }
        if let corner, !preview {
            if event.modifierFlags.contains(.shift) {
                if let q=before.movingCornerPreservingAngles(corner,to:normalized(p)){quad=q}
            } else {var q=quad;q.points[corner]=normalized(p);if q.valid {quad=q}}
        }
        else if let grip=splitGrip,let old=splitBefore,let u=across(p),!preview {
            switch grip {
            case .top:split=PageSplit(top:u,bottom:old.bottom).clamped
            case .bottom:split=PageSplit(top:old.top,bottom:u).clamped
            case .line:split=old.moved(by:u-splitStart)
            }
        }
        else if let edge,!preview {
            let r=imageRect
            if let q=before.movingEdge(edge,by:turn.photographDelta(Point((p.x-start.x)/r.width,(p.y-start.y)/r.height))){quad=q}
        }
        else if moving && !preview {
            let r=imageRect,d=turn.photographDelta(Point((p.x-start.x)/r.width,(p.y-start.y)/r.height))
            let q=Quad(before.points.map{Point($0.x+d.x,$0.y+d.y)});if q.valid {quad=q}
        } else {pan=CGPoint(x:oldPan.x+p.x-start.x,y:oldPan.y+p.y-start.y);needsDisplay=true}
    }
    override func mouseUp(with event: NSEvent) {
        showMagnifier=false
        if panning {panning=false;needsDisplay=true;return}
        defer {moving=false}
        if zoneMode {
            // One drag draws one zone; a slip of the mouse draws none.
            let drawn=zoneDraft;zoneMode=false;zoneStart=nil;zoneDraft=nil
            if let drawn,drawn.isUsable {onZoneCommit?(drawn)}
            return
        }
        if smudgeMode {
            let stroke=smudgeDraft;smudgeDraft=[];needsDisplay=true
            if !stroke.isEmpty,!preview {onSmudgeCommit?(stroke)}
            return
        }
        if cloneMode {
            let stroke=cloneDraft;cloneDraft=[];needsDisplay=true
            if !stroke.isEmpty,!preview,let offset=cloneOffset {onCloneCommit?(stroke,offset)}
            return
        }
        if splitGrip != nil {splitGrip=nil;if let split,split != splitBefore {onSplitCommit?(split)}}
        else if quad != before {onCommit?(quad)}
        needsDisplay=true
    }
    /// A mouse wheel zooms about the pointer. A trackpad's two-finger scroll still moves the picture; it zooms by pinching.
    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas else {pan.x-=event.scrollingDeltaX;pan.y-=event.scrollingDeltaY;needsDisplay=true;return}
        guard event.scrollingDeltaY != 0 else {return}
        zoom(by:pow(1.12,max(-4,min(4,event.scrollingDeltaY))),about:convert(event.locationInWindow,from:nil))
    }
    /// Changes the zoom so that the part of the picture under `point` stays under it.
    func zoom(by factor: CGFloat, about point: CGPoint) {
        let old=zoom,new=min(8,max(0.5,old*factor));guard new != old,image != nil else {return}
        let r=imageRect,centre=CGPoint(x:r.midX,y:r.midY),scale=new/old
        pan=CGPoint(x:point.x-bounds.midX-(point.x-centre.x)*scale,y:point.y-bounds.midY-(point.y-centre.y)*scale)
        zoom=new
    }
    override func magnify(with event: NSEvent) {zoom=min(8,max(0.5,zoom*(1+event.magnification)))}
    override func keyDown(with event: NSEvent) {
        if event.keyCode==36 {onAccept?();return}
        if event.charactersIgnoringModifiers=="z",event.modifierFlags.contains(.command){onUndo?();return}
        if keyboardSelection,[123,124,125,126].contains(event.keyCode) {
            let mapping:[UInt16:String]=[123:"a",124:"d",125:"s",126:"w"]
            nudge(mapping[event.keyCode]!,large:event.modifierFlags.contains(.shift));return
        }
        if event.keyCode==123 {onNavigate?(-1)} else if event.keyCode==124 {onNavigate?(1)} else {super.keyDown(with:event)}
    }
    var selectedCorner: Int? {corner}
    var hasSelection: Bool {corner != nil || edge != nil}
    var selectedEdge: Int? {edge}
    func selectCorner(_ i: Int, keyboard:Bool=false){keyboardSelection=keyboard;magnifierOpposite=false;corner=i;edge=nil;showMagnifier=true;needsDisplay=true}
    func selectEdge(_ i: Int, keyboard:Bool=false){keyboardSelection=keyboard;edge=i;corner=nil;showMagnifier=false;needsDisplay=true}
    func releaseCorner(){keyboardSelection=false;corner=nil;edge=nil;showMagnifier=false;needsDisplay=true}
    func nudge(_ key: String, large: Bool){
        guard image != nil,!preview else{return}
        // A step is so many pixels of the picture as it is shown; the keys move it the way they point on screen.
        let step=large ? 10.0:1.0,shown=shownSize
        let d=turn.photographDelta(Point((key=="d" ? step:key=="a" ? -step:0)/Double(shown.width),(key=="s" ? step:key=="w" ? -step:0)/Double(shown.height)))
        let dx=d.x,dy=d.y
        var q=quad
        if let c=corner {q.points[c].x+=dx;q.points[c].y+=dy;showMagnifier=true}
        else if let edge,let moved=quad.movingEdge(edge,by:Point(dx,dy)){q=moved}
        else{return}
        if q.valid{quad=q;onCommit?(q)}
    }
    func fit(){keyboardSelection=false;zoom=1;pan = .zero;corner=nil;edge=nil;showMagnifier=false;needsDisplay=true}
}

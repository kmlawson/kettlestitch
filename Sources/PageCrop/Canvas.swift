import AppKit
import CropCore

final class CropCanvas: NSView {
    static let emptyProjectMessage="Drop photographs or a folder here\nor choose File ▸ Import Photographs.\n\nYour originals stay untouched."
    var placeholder=CropCanvas.emptyProjectMessage {didSet{needsDisplay=true}}
    var image: CGImage? {didSet {needsDisplay=true}}
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
    override var isFlipped: Bool {true}
    override var acceptsFirstResponder: Bool {true}
    var imageRect: CGRect {
        guard let image else {return .zero}
        let scale=min((bounds.width-64)/CGFloat(image.width),(bounds.height-64)/CGFloat(image.height))*zoom
        let size=CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
        return CGRect(x:(bounds.width-size.width)/2+pan.x,y:(bounds.height-size.height)/2+pan.y,width:size.width,height:size.height)
    }
    func position(_ p: Point) -> CGPoint {let r=imageRect;return CGPoint(x:r.minX+p.x*r.width,y:r.minY+p.y*r.height)}
    func normalized(_ p: CGPoint) -> Point {let r=imageRect;return Point(min(1,max(0,(p.x-r.minX)/r.width)),min(1,max(0,(p.y-r.minY)/r.height)))}
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite:0.105,alpha:1).setFill();bounds.fill()
        guard let image else {
            let s=placeholder
            let centred=NSMutableParagraphStyle();centred.alignment = .center
            let attrs: [NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.lightGray,.paragraphStyle:centred]
            (s as NSString).draw(in:CGRect(x:40,y:bounds.midY-50,width:max(0,bounds.width-80),height:120),withAttributes:attrs);return
        }
        NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:imageRect)
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
            NSColor.black.setFill();box.fill();NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:dest)
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
    override func resetCursorRects(){if zoneMode {addCursorRect(bounds,cursor:.crosshair)}}
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
        keyboardSelection=false;window?.makeFirstResponder(self);start=convert(event.locationInWindow,from:nil);oldPan=pan;before=quad;showMagnifier=false;magnifierOpposite=false;edge=nil;corner=nil;splitGrip=nil;splitBefore=split
        guard !preview else {return}
        if zoneMode {zoneStart=outputPosition(start);zoneDraft=nil;return}
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
        }
        showMagnifier=corner != nil;needsDisplay=true
    }
    override func mouseDragged(with event: NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if zoneMode,!preview {if let a=zoneStart,let b=outputPosition(p){zoneDraft=PictureZone(from:a,to:b);needsDisplay=true};return}
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
            if let q=before.movingEdge(edge,by:Point((p.x-start.x)/r.width,(p.y-start.y)/r.height)){quad=q}
        }
        else if moving && !preview {
            let r=imageRect,dx=(p.x-start.x)/r.width,dy=(p.y-start.y)/r.height
            let q=Quad(before.points.map{Point($0.x+dx,$0.y+dy)});if q.valid {quad=q}
        } else {pan=CGPoint(x:oldPan.x+p.x-start.x,y:oldPan.y+p.y-start.y);needsDisplay=true}
    }
    override func mouseUp(with event: NSEvent) {
        showMagnifier=false
        if zoneMode {
            // One drag draws one zone; a slip of the mouse draws none.
            let drawn=zoneDraft;zoneMode=false;zoneStart=nil;zoneDraft=nil
            if let drawn,drawn.isUsable {onZoneCommit?(drawn)}
            return
        }
        if splitGrip != nil {splitGrip=nil;if let split,split != splitBefore {onSplitCommit?(split)}}
        else if quad != before {onCommit?(quad)}
        needsDisplay=true
    }
    override func scrollWheel(with event: NSEvent) {pan.x-=event.scrollingDeltaX;pan.y-=event.scrollingDeltaY;needsDisplay=true}
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
        guard let image,!preview else{return}
        let step=large ? 10.0:1.0
        let dx=(key=="d" ? step:key=="a" ? -step:0)/Double(image.width)
        let dy=(key=="s" ? step:key=="w" ? -step:0)/Double(image.height)
        var q=quad
        if let c=corner {q.points[c].x+=dx;q.points[c].y+=dy;showMagnifier=true}
        else if let edge,let moved=quad.movingEdge(edge,by:Point(dx,dy)){q=moved}
        else{return}
        if q.valid{quad=q;onCommit?(q)}
    }
    func fit(){keyboardSelection=false;zoom=1;pan = .zero;corner=nil;edge=nil;showMagnifier=false;needsDisplay=true}
}

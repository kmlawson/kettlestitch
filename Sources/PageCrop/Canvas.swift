import AppKit
import CropCore

final class CropCanvas: NSView {
    static let emptyProjectMessage="Open a folder of page photographs\nYour originals stay untouched."
    var placeholder=CropCanvas.emptyProjectMessage {didSet{needsDisplay=true}}
    var image: CGImage? {didSet {needsDisplay=true}}
    var quad=Quad.full {didSet{needsDisplay=true}}
    var preview=false {didSet{needsDisplay=true}}
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
            let attrs: [NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:20),.foregroundColor:NSColor.lightGray]
            (s as NSString).draw(in:CGRect(x:60,y:bounds.midY-30,width:bounds.width-100,height:90),withAttributes:attrs);return
        }
        NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:imageRect)
        guard !preview else {return}
        let path=NSBezierPath();path.move(to:position(quad.points[0]));for p in quad.points.dropFirst(){path.line(to:position(p))};path.close()
        let shade=NSBezierPath(rect:imageRect);shade.append(path);shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.52).setFill();shade.fill()
        NSColor.systemMint.setStroke();path.lineWidth=2;path.stroke()
        for (i,p) in quad.points.enumerated() {
            let pos=position(p),r=CGRect(x:pos.x-6,y:pos.y-6,width:12,height:12)
            NSColor.white.setFill();NSBezierPath(ovalIn:r).fill()
            if i==corner {NSColor.systemMint.setStroke();let ring=NSBezierPath(ovalIn:r.insetBy(dx:-4,dy:-4));ring.lineWidth=2;ring.stroke()}
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
            NSColor.black.setFill();box.fill();NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:dest)
            NSColor.systemMint.setStroke();let cross=NSBezierPath();cross.move(to:CGPoint(x:box.midX-12,y:box.midY));cross.line(to:CGPoint(x:box.midX+12,y:box.midY));cross.move(to:CGPoint(x:box.midX,y:box.midY-12));cross.line(to:CGPoint(x:box.midX,y:box.midY+12));cross.stroke();NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func mouseDown(with event: NSEvent) {
        keyboardSelection=false;window?.makeFirstResponder(self);start=convert(event.locationInWindow,from:nil);oldPan=pan;before=quad;showMagnifier=false;magnifierOpposite=false;edge=nil;corner=nil
        guard !preview else {return}
        corner=(0..<4).min{hypot(position(quad.points[$0]).x-start.x,position(quad.points[$0]).y-start.y)<hypot(position(quad.points[$1]).x-start.x,position(quad.points[$1]).y-start.y)}
        if let c=corner, hypot(position(quad.points[c]).x-start.x,position(quad.points[c]).y-start.y)>24 {corner=nil}
        moving=event.modifierFlags.contains(.option)
        if moving {corner=nil}
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
        if let corner, !preview {
            if event.modifierFlags.contains(.shift) {
                if let q=before.movingCornerPreservingAngles(corner,to:normalized(p)){quad=q}
            } else {var q=quad;q.points[corner]=normalized(p);if q.valid {quad=q}}
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
    override func mouseUp(with event: NSEvent) {showMagnifier=false;if quad != before {onCommit?(quad)};needsDisplay=true}
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

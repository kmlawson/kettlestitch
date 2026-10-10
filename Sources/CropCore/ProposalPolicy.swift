import Foundation

/// Hard limits for automatic proposals only. Manual crops remain unrestricted.
public enum ProposalPolicy {
    /// Soft prior for whole-book spreads: perspective should not stretch only one side.
    /// Measure against the spread's own horizontal axis so camera rotation is harmless.
    public static func unevenPerspectivePenalty(_ quad:Quad,imageAspectRatio:Double)->Double {
        guard quad.valid,imageAspectRatio.isFinite,imageAspectRatio>0 else{return 0}
        let p=quad.points.map{Point($0.x*imageAspectRatio,$0.y)}
        let top=Point(p[1].x-p[0].x,p[1].y-p[0].y)
        let bottom=Point(p[2].x-p[3].x,p[2].y-p[3].y)
        let tl=hypot(top.x,top.y),bl=hypot(bottom.x,bottom.y)
        let ux=top.x/tl+bottom.x/bl,uy=top.y/tl+bottom.y/bl
        let length=hypot(ux,uy),x=ux/length,y=uy/length
        func lean(_ a:Point,_ b:Point)->Double {
            let dx=b.x-a.x,dy=b.y-a.y
            return abs(atan2(dx*x+dy*y,dx*(-y)+dy*x))*180 / .pi
        }
        let imbalance=abs(lean(p[0],p[3])-lean(p[1],p[2]))
        // Three degrees of tolerance allows small capture and detection imperfections.
        return min(0.35,max(0,imbalance-3)*0.035)
    }
    public static let minimumArea = 0.65
    public static func accepts(_ quad: Quad, imageAspectRatio: Double) -> Bool {
        guard quad.valid, quad.area >= minimumArea, imageAspectRatio.isFinite, imageAspectRatio > 0 else { return false }
        // Angles and lengths must be evaluated in image pixels, not a stretched unit square.
        let p = quad.points.map { Point($0.x * imageAspectRatio, $0.y) }
        let sides = (0..<4).map { i in Point(p[(i+1)%4].x-p[i].x, p[(i+1)%4].y-p[i].y) }
        let lengths = sides.map { hypot($0.x, $0.y) }
        for i in 0..<4 {
            let incoming = sides[(i+3)%4], outgoing = sides[i]
            let cosine = -(incoming.x*outgoing.x + incoming.y*outgoing.y) / (lengths[(i+3)%4]*lengths[i])
            let angle = acos(min(1,max(-1,cosine))) * 180 / .pi
            guard (70...110).contains(angle) else { return false }
        }
        for i in 0..<2 {
            let ratio = max(lengths[i],lengths[i+2]) / min(lengths[i],lengths[i+2])
            guard ratio <= 1.4 else { return false }
            let a=sides[i], b=sides[i+2]
            let cosine = -(a.x*b.x+a.y*b.y)/(lengths[i]*lengths[i+2])
            guard acos(min(1,max(-1,cosine))) * 180 / .pi <= 20 else { return false }
        }
        return true
    }
}

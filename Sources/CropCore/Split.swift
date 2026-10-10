import Foundation
import CoreGraphics

/// A dividing line between two facing pages. `top` and `bottom` are fractions across the corrected,
/// rotated output from its left edge, so the line follows the crop when the crop is edited.
public struct PageSplit: Codable, Equatable {
    public var top: Double
    public var bottom: Double
    public init(top: Double, bottom: Double) {self.top=top;self.bottom=bottom}
    public static let centre = PageSplit(top:0.5,bottom:0.5)
    /// Neither page may be thinner than this fraction of the spread.
    public static let margin = 0.03
    public var clamped: PageSplit {
        func limit(_ v: Double) -> Double {v.isFinite ? min(1-PageSplit.margin,max(PageSplit.margin,v)):0.5}
        return PageSplit(top:limit(top),bottom:limit(bottom))
    }
    /// The same line after the output is turned. A half turn mirrors it; a quarter turn leaves no
    /// vertical line to keep, so the split has to be proposed again.
    public func rotated(quarterTurns: Int) -> PageSplit? {
        switch ((quarterTurns%4)+4)%4 {
        case 0:return self
        case 2:return PageSplit(top:1-bottom,bottom:1-top)
        default:return nil
        }
    }
    /// Shifts both ends together, keeping the tilt and stopping at the margins.
    public func moved(by delta: Double) -> PageSplit {
        let d=min(1-PageSplit.margin-max(top,bottom),max(PageSplit.margin-min(top,bottom),delta))
        return PageSplit(top:top+d,bottom:bottom+d).clamped
    }
}
/// Projective map from the unit square (origin top-left) onto four corners given as TL, TR, BR, BL.
public struct Homography {
    let m: [Double]
    public init?(unitSquareTo c: [Point]) {
        guard c.count == 4 else {return nil}
        let dx1=c[1].x-c[2].x,dx2=c[3].x-c[2].x,sx=c[0].x-c[1].x+c[2].x-c[3].x
        let dy1=c[1].y-c[2].y,dy2=c[3].y-c[2].y,sy=c[0].y-c[1].y+c[2].y-c[3].y
        let det=dx1*dy2-dx2*dy1
        guard abs(det)>1e-12 else {return nil}
        let g=(sx*dy2-dx2*sy)/det,h=(dx1*sy-sx*dy1)/det
        m=[c[1].x-c[0].x+g*c[1].x,c[3].x-c[0].x+h*c[3].x,c[0].x,
           c[1].y-c[0].y+g*c[1].y,c[3].y-c[0].y+h*c[3].y,c[0].y,
           g,h,1]
    }
    public func map(_ u: Double, _ v: Double) -> Point {
        let w=m[6]*u+m[7]*v+m[8]
        return Point((m[0]*u+m[1]*v+m[2])/w,(m[3]*u+m[4]*v+m[5])/w)
    }
    /// The unit-square position that maps to `p`.
    public func inverse(_ p: Point) -> (u: Double, v: Double)? {
        let a=m[4]*m[8]-m[5]*m[7],b=m[2]*m[7]-m[1]*m[8],c=m[1]*m[5]-m[2]*m[4]
        let d=m[5]*m[6]-m[3]*m[8],e=m[0]*m[8]-m[2]*m[6],f=m[2]*m[3]-m[0]*m[5]
        let g=m[3]*m[7]-m[4]*m[6],h=m[1]*m[6]-m[0]*m[7],i=m[0]*m[4]-m[1]*m[3]
        let w=g*p.x+h*p.y+i
        guard abs(w)>1e-12 else {return nil}
        return ((a*p.x+b*p.y+c)/w,(d*p.x+e*p.y+f)/w)
    }
}
public enum SplitGeometry {
    /// The crop's corners in the order they appear in the rotated output: TL, TR, BR, BL.
    public static func outputCorners(_ quad: Quad, rotation: Int) -> [Point] {
        let r=((rotation%4)+4)%4
        return (0..<4).map{quad.points[($0+4-r)%4]}
    }
    static func transform(_ quad: Quad, _ rotation: Int) -> Homography? {
        quad.points.count == 4 ? Homography(unitSquareTo:outputCorners(quad,rotation:rotation)):nil
    }
    /// The split's ends on the photograph: first the end on the output's top edge, then the bottom.
    public static func line(_ split: PageSplit, quad: Quad, rotation: Int) -> (Point, Point)? {
        guard let h=transform(quad,rotation) else {return nil}
        return (h.map(split.top,0),h.map(split.bottom,1))
    }
    /// Where a point on the photograph falls in the output: `u` across, `v` down.
    public static func position(of point: Point, quad: Quad, rotation: Int) -> (u: Double, v: Double)? {
        transform(quad,rotation)?.inverse(point)
    }
    /// The two pages as crops of the photograph, left then right as seen in the output.
    public static func parts(_ split: PageSplit, quad: Quad, rotation: Int) -> [Quad]? {
        guard let (a,b)=line(split.clamped,quad:quad,rotation:rotation) else {return nil}
        let o=outputCorners(quad,rotation:rotation),r=((rotation%4)+4)%4
        // Back from output order to the stored order, which stays clockwise.
        func stored(_ corners: [Point]) -> Quad {var p=corners;for i in 0..<4 {p[(i+4-r)%4]=corners[i]};return Quad(p)}
        let left=stored([o[0],a,b,o[3]]),right=stored([a,o[1],o[2],b])
        return left.valid && right.valid ? [left,right]:nil
    }
}
public struct SplitProposal: Equatable {
    public var split: PageSplit
    /// False when no fold or gap stood out and the centre was used instead.
    public var confident: Bool
}
/// Finds the fold between facing pages in the corrected crop.
///
/// Two cues are combined, following ScanTailor's page-split stage: a near-vertical dark line or shadow
/// (its fold-line finder), and a column with no print between two bodies of content (its whitespace cut).
/// The search is limited to the middle of the spread and falls back to the centre, as ScanTailor does.
///
/// A `guide` is the split of the page before, most likely the same book: the fold is expected at the same
/// fraction across the crop, whatever the crop's size. The search then centres on the guide, and the guide
/// is the fallback when no fold stands out.
public enum SplitDetector {
    /// The split to go by for the page at `index`: that of the nearest earlier page that has one and is turned the same way.
    public static func guide(for index: Int, in pages: [Page]) -> PageSplit? {
        guard pages.indices.contains(index) else {return nil}
        return pages[..<index].last{$0.split != nil && $0.rotation == pages[index].rotation}?.split
    }
    public static func detect(_ image: CGImage, quad: Quad, rotation: Int, guide: PageSplit? = nil) throws -> SplitProposal {
        let corrected=try Imaging.corrected(image,quad:quad,rotation:rotation)
        let w=min(640,corrected.width),h=max(8,Int((Double(corrected.height)*Double(w)/Double(corrected.width)).rounded()))
        var bytes=[UInt8](repeating:0,count:w*h)
        bytes.withUnsafeMutableBytes{buffer in
            if let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) {
                c.interpolationQuality = .medium;c.draw(corrected,in:CGRect(x:0,y:0,width:w,height:h))
            }
        }
        return analyse(bytes.map{Double($0)/255},width:w,height:h,guide:guide)
    }
    /// `gray` is row-major from the top, 0 black to 1 white.
    public static func analyse(_ gray: [Double], width w: Int, height h: Int, guide: PageSplit? = nil) -> SplitProposal {
        let guide=guide?.clamped,fallback=SplitProposal(split:guide ?? .centre,confident:false)
        guard w>=40,h>=20,gray.count == w*h else {return fallback}
        // Where the fold is expected, and how far from it the search reaches.
        let expected=guide.map{($0.top+$0.bottom)/2} ?? 0.5,expectedShift=guide.map{Int((($0.bottom-$0.top)*Double(w)).rounded())} ?? 0
        let edge=max(2,Int((PageSplit.margin*Double(w)).rounded(.up)))
        let low=guide == nil ? w/5:max(edge,min(w/5,Int(expected*Double(w))-w/5)),high=guide == nil ? w-w/5:min(w-edge,max(w-w/5,Int(expected*Double(w))+w/5))
        let first=guide == nil ? w/4:max(low,min(w/4,Int(expected*Double(w))-w/8)),last=guide == nil ? 3*w/4:min(high-1,max(3*w/4,Int(expected*Double(w))+w/8))
        // Rows near the top and bottom often show the table or the book's edge.
        let rows=Array(stride(from:h/16,to:h-h/16,by:max(1,h/240)))
        let narrow=max(2,w/90),broad=max(6,w/24)
        // Per-row running sums give box means in constant time.
        var sums=[Double](repeating:0,count:(w+1)*h)
        for y in 0..<h {var total=0.0;for x in 0..<w {total+=gray[y*w+x];sums[y*(w+1)+x+1]=total}}
        func mean(_ y: Int, _ from: Int, _ to: Int) -> Double {
            let a=max(0,from),b=min(w-1,to)
            return a>b ? 1:(sums[y*(w+1)+b+1]-sums[y*(w+1)+a])/Double(b-a+1)
        }
        /// How much darker a point is than the paper on both sides of it, 0...1.
        func valley(_ y: Int, _ x: Int, _ reach: Int) -> Double {
            let centre=mean(y,x-1,x+1),sides=min(mean(y,x-reach-2,x-reach),mean(y,x+reach,x+reach+2))
            return min(1,max(0,(sides-centre)/max(0.08,sides))/0.3)
        }
        // Valley strength at the sampled rows, computed once so every candidate line is a sum of lookups.
        // These rows reach almost to the top and bottom: a fold crosses the whole page, a printed rule or frame does not.
        let across=Array(stride(from:h/50,to:h-h/50,by:max(1,h/240))),bands=20
        var folds=[Double](repeating:0,count:across.count*w)
        for (r,y) in across.enumerated() {for x in low..<high {folds[r*w+x]=max(valley(y,x,narrow),0.8*valley(y,x,broad))}}
        // Print shows as horizontal contrast; a fold's shadow or an empty gutter does not.
        var contrast=[Double](repeating:0,count:w+1)
        for x in 1..<w-1 {var total=0.0;for y in rows {total+=abs(gray[y*w+x+1]-gray[y*w+x-1])};contrast[x+1]=contrast[x]+total/Double(rows.count)}
        contrast[w]=contrast[w-1]
        func print(_ from: Int, _ to: Int) -> Double {let a=max(0,from),b=min(w-1,to);return a>b ? 0:(contrast[b+1]-contrast[a])/Double(b-a+1)}
        let typical=(0..<w).map{print($0-narrow,$0+narrow)}.sorted()[w/2]
        let printed=typical>0.01
        /// How free of print the paper beside column `x` is, between `near` and `far` pixels away, 0...1.
        func quiet(_ x: Int, _ near: Int, _ far: Int) -> Double {
            let beside=max(print(x-far,x-near),print(x+near,x+far))
            return printed ? min(1,max(0,1-beside/typical)):(beside<0.01 ? 1:0)
        }
        // A rule or a stroke of print is a dark line too, but it has print beside it; a fold sits in the inner margins.
        func margin(_ x: Int) -> Double {0.6*quiet(x,narrow+1,2*narrow+2)+0.4*quiet(x,2*narrow+3,4*narrow)}

        var best=(score:-Double.infinity,top:w/2,bottom:w/2,fold:0.0,gap:0.0)
        // With a guide: the clearest line through each column, to find the one nearest the guide afterwards.
        var lines=[(fold:Double,bottom:Int)](repeating:(0,0),count:guide == nil ? 0:w)
        let lean=max(1,w/20)
        for top in stride(from:first,through:last,by:1) {
            for shift in stride(from:-lean,through:lean,by:2) {
                let bottom=top+shift
                guard bottom>=low,bottom<high else {continue}
                var fold=0.0,stretch=[Double](repeating:0,count:bands),counts=[Double](repeating:0,count:bands)
                for (r,y) in across.enumerated() {
                    let strength=folds[r*w+top+shift*y/(h-1)],band=r*bands/across.count
                    fold+=strength;stretch[band]+=strength;counts[band]+=1
                }
                fold/=Double(across.count)
                // The two weakest stretches of the line. Where they fall well below the rest, it stops short and is no fold.
                let weakest=zip(stretch,counts).map{$1>0 ? $0/$1:0}.sorted().prefix(2).reduce(0,+)/2
                if fold>0 {let whole=min(1,weakest/(0.5*fold));fold*=whole*whole}
                let middle=(top+bottom)/2,gap=margin(middle)
                let off=abs(Double(middle)/Double(w)-expected)
                // The page before says more about where the fold is than the centre of the crop does.
                // It weighs heavily: evidence a few percent of the width away from it counts for less than half.
                let drift=guide == nil ? 0.9*max(0,off-0.03):1.4*max(0,off-0.015)
                let trust=guide == nil ? 1:0.3+0.7*exp(-(off/0.025)*(off/0.025))
                let score=(gap*(0.45+0.8*fold)+0.2*fold)*trust-drift-0.25*Double(abs(shift-expectedShift))/Double(w)
                if score>best.score {best=(score,top,bottom,fold,gap)}
                // A line with print right beside it is a rule or a stroke of text.
                if guide != nil,gap>0.3,fold>lines[top].fold {lines[top]=(fold,bottom)}
            }
        }
        if guide != nil {
            // Every line that looks like a fold is a peak among its neighbours; the one nearest the guide is taken,
            // not the darkest. Only when there is none does the weighted search above decide.
            let reach=2*narrow
            let peaks=(first...last).filter{x in lines[x].fold>0.22 && !(max(first,x-reach)...min(last,x+reach)).contains{lines[$0].fold>lines[x].fold}}
            func distance(_ x: Int) -> Double {abs((Double(x+lines[x].bottom)/2+0.5)/Double(w)-expected)}
            if let x=peaks.min(by:{distance($0)<distance($1)}) {
                return SplitProposal(split:PageSplit(top:(Double(x)+0.5)/Double(w),bottom:(Double(lines[x].bottom)+0.5)/Double(w)).clamped,confident:true)
            }
        }
        let confident=best.fold>0.22 || (printed && best.gap>0.75)
        guard confident else {return fallback}
        return SplitProposal(split:PageSplit(top:(Double(best.top)+0.5)/Double(w),bottom:(Double(best.bottom)+0.5)/Double(w)).clamped,confident:true)
    }
}

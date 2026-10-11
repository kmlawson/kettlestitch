import Foundation
import CoreGraphics

public struct SkewEstimate: Equatable {
    /// Degrees the content is turned clockwise as seen; deskewing turns it back by the same amount.
    public var angle: Double
    public var confident: Bool
}
/// Finds the tilt of text by trying angles and keeping the one at which lines (or columns) of print
/// collapse into the sharpest profile, the approach ScanTailor's deskew stage takes.
public enum SkewDetector {
    public static let limit = 15.0
    /// `gray` is row-major from the top, 0 black to 1 white.
    public static func analyse(_ gray: [Double], width w: Int, height h: Int) -> SkewEstimate {
        let none=SkewEstimate(angle:0,confident:false)
        guard w>=20,h>=20,gray.count == w*h else {return none}
        // Print is whatever is clearly darker than the paper around it. Judging each point against its
        // neighbourhood ignores uneven lighting and the insides of dark pictures.
        var sums=[Double](repeating:0,count:(w+1)*(h+1))
        for y in 0..<h {var row=0.0;for x in 0..<w {row+=gray[y*w+x];sums[(y+1)*(w+1)+x+1]=sums[y*(w+1)+x+1]+row}}
        let reach=max(4,min(w,h)/40)
        var xs:[Double]=[],ys:[Double]=[]
        for y in 0..<h {for x in 0..<w {
            let x0=max(0,x-reach),x1=min(w,x+reach+1),y0=max(0,y-reach),y1=min(h,y+reach+1)
            let around=(sums[y1*(w+1)+x1]-sums[y0*(w+1)+x1]-sums[y1*(w+1)+x0]+sums[y0*(w+1)+x0])/Double((x1-x0)*(y1-y0))
            if gray[y*w+x]<around-0.08 {xs.append(Double(x));ys.append(Double(y))}
        }}
        guard xs.count>=200 else {return none}
        let span=Int(hypot(Double(w),Double(h)))+2
        func profile(_ degrees: Double, columns: Bool) -> [Double] {
            let a=degrees * .pi/180,c=cos(a),s=sin(a)
            var bins=[Double](repeating:0,count:2*span)
            for i in xs.indices {bins[Int(columns ? xs[i]*c+ys[i]*s:ys[i]*c-xs[i]*s)+span]+=1}
            return bins
        }
        /// How abruptly the profile across lines (or columns) rises and falls when the page is turned back by `degrees`:
        /// level lines of print give sharp steps between line and gap.
        func sharpness(_ degrees: Double, columns: Bool) -> Double {
            let bins=profile(degrees,columns:columns)
            var total=0.0
            for i in 1..<bins.count {let d=bins[i]-bins[i-1];total+=d*d}
            return total
        }
        var best=(ratio:0.0,angle:0.0,columns:false)
        for columns in [false,true] {
            let coarse=stride(from:-8.0,through:8.0,by:0.5).map{($0,sharpness($0,columns:columns))}
            guard let peak=coarse.max(by:{$0.1<$1.1}) else {continue}
            var top=peak
            for step in -9...9 {let a=peak.0+Double(step)*0.05,v=sharpness(a,columns:columns);if v>top.1 {top=(a,v)}}
            let typical=coarse.map{$0.1}.sorted()[coarse.count/2]
            let ratio=typical>0 ? top.1/typical:0
            if ratio>best.ratio {best=(ratio,top.0,columns)}
        }
        guard best.ratio>=1.5 else {return none}
        // One picture with straight sides also gives sharp steps, but only a pair of them; print gives a row of lines.
        let bins=profile(best.angle,columns:best.columns),occupied=bins.filter{$0>0}.sorted()
        guard !occupied.isEmpty else {return none}
        let level=occupied[occupied.count*9/10]/2
        var lines=0
        for i in 1..<bins.count where bins[i]>=level && bins[i-1]<level {lines+=1}
        guard lines>=5 else {return none}
        return SkewEstimate(angle:(best.angle*100).rounded()/100,confident:true)
    }
    public static func detect(_ image: CGImage) -> SkewEstimate {
        let scale=min(1,600/Double(max(image.width,image.height)))
        let w=max(1,Int(Double(image.width)*scale)),h=max(1,Int(Double(image.height)*scale))
        var bytes=[UInt8](repeating:0,count:w*h)
        bytes.withUnsafeMutableBytes{buffer in
            if let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) {
                c.interpolationQuality = .medium;c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
            }
        }
        return analyse(bytes.map{Double($0)/255},width:w,height:h)
    }
    /// One angle per output part (the whole crop, or left and right page), or nil when no part shows a clear tilt.
    public static func detect(_ source: CGImage, page: Page) throws -> [Double]? {
        let parts=try Exporter.quads(for:page,options:ExportOptions()).map{quad->SkewEstimate in
            detect(try Imaging.corrected(source,quad:quad,rotation:page.rotation))
        }
        return angles(from:parts)
    }
    /// Tilts below this are within the measurement's own error and are not worth resampling the page for.
    public static let minimumUseful = 0.15
    /// The angles to apply for a set of measurements: 0 for parts that are level or unclear, nil if no part needs turning.
    public static func angles(from estimates: [SkewEstimate]) -> [Double]? {
        let angles=estimates.map{$0.confident && abs($0.angle)>=minimumUseful-1e-9 ? $0.angle:0}
        return angles.contains{$0 != 0} ? angles:nil
    }
}
/// Removes specks from black-and-white output. A small mark beside print (a dot, an accent) is kept,
/// as ScanTailor's despeckler keeps them.
public enum Despeckle {
    /// The largest area, in pixels, still treated as a speck.
    public static func limit(level: Int, longSide: Int) -> Int {
        let l=min(3,max(0,level))
        guard l>0 else {return 0}
        let scale=Double(longSide)/1500
        return max([0,2,6,14][l],Int((Double([0,1,3,8][l])*scale*scale).rounded()))
    }
    /// `pixels` holds one byte per pixel, row-major; values below 128 are black.
    public static func clean(_ pixels: inout [UInt8], width w: Int, height h: Int, level: Int) {
        let limit=limit(level:level,longSide:max(w,h))
        guard limit>0,w>0,h>0,pixels.count == w*h else {return}
        var labels=[Int32](repeating:0,count:w*h)
        var areas:[Int]=[0],boxes:[(Int,Int,Int,Int)]=[(0,0,0,0)]
        var stack:[Int]=[]
        for start in 0..<w*h where pixels[start]<128 && labels[start] == 0 {
            let label=Int32(areas.count)
            var area=0,minX=w,minY=h,maxX=0,maxY=0
            labels[start]=label;stack.append(start)
            while let at=stack.popLast() {
                let x=at%w,y=at/w
                area+=1;minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                for ny in max(0,y-1)...min(h-1,y+1) {for nx in max(0,x-1)...min(w-1,x+1) {
                    let n=ny*w+nx
                    if pixels[n]<128,labels[n] == 0 {labels[n]=label;stack.append(n)}
                }}
            }
            areas.append(area);boxes.append((minX,minY,maxX,maxY))
        }
        let reach=Int(2*Double(limit).squareRoot())+1
        var remove=[Bool](repeating:false,count:areas.count)
        for label in 1..<areas.count where areas[label]<=limit {
            let (minX,minY,maxX,maxY)=boxes[label]
            var beside=false
            search: for y in max(0,minY-reach)...min(h-1,maxY+reach) {for x in max(0,minX-reach)...min(w-1,maxX+reach) {
                let other=Int(labels[y*w+x])
                if other != 0,areas[other]>limit {beside=true;break search}
            }}
            remove[label] = !beside
        }
        for i in 0..<w*h where remove[Int(labels[i])] {pixels[i]=255}
    }
}
/// A rectangle of the corrected output, in fractions of its width and height, that keeps its tones
/// when the rest of the page is reduced to black and white.
public struct PictureZone: Codable, Equatable {
    public var minU: Double
    public var minV: Double
    public var maxU: Double
    public var maxV: Double
    public init(from a: (Double,Double), to b: (Double,Double)) {
        func unit(_ v: Double) -> Double {v.isFinite ? min(1,max(0,v)):0}
        minU=unit(min(a.0,b.0));maxU=unit(max(a.0,b.0));minV=unit(min(a.1,b.1));maxV=unit(max(a.1,b.1))
    }
    public var isUsable: Bool {maxU-minU>=0.02 && maxV-minV>=0.02}
    public func contains(_ u: Double, _ v: Double) -> Bool {u>=minU && u<=maxU && v>=minV && v<=maxV}
    /// The zone's corners on the photograph, in output order.
    public func outline(quad: Quad, rotation: Int) -> [Point]? {
        guard let h=SplitGeometry.transform(quad,rotation) else {return nil}
        return [h.map(minU,minV),h.map(maxU,minV),h.map(maxU,maxV),h.map(minU,maxV)]
    }
}
/// One stroke of the smudge brush, which blurs what it passes over so that it cannot be read.
/// It lies on the photograph, so it stays on the same print when the crop or split changes.
public struct Smudge: Codable, Equatable {
    /// The brush's path, in fractions of the photograph's width and height from its top-left corner.
    public var points: [Point]
    /// Half the stroke's width, as a fraction of the photograph's longer side.
    public var radius: Double
    /// How heavily the print is blurred, 0...1.
    public var strength: Double
    /// How much gray grain is laid over the blur, 0 (none) to 1, to make the smudge stand out less from the paper
    /// around it. Optional so that strokes saved before it existed still decode; nil is the standard amount.
    public var grain: Double?
    public init(points: [Point], radius: Double, strength: Double, grain: Double? = nil) {
        self.points=points;self.radius=min(0.25,max(0.002,radius.isFinite ? radius:0.02));self.strength=min(1,max(0,strength.isFinite ? strength:0.5))
        self.grain=grain.map{min(1,max(0,$0.isFinite ? $0:Imaging.smudgeGrain))}
    }
}
/// One stroke of the clone brush: what it passes over is replaced by a copy of the photograph a fixed distance away.
public struct CloneStroke: Codable, Equatable {
    /// The brush's path, in fractions of the photograph from its top-left corner.
    public var points: [Point]
    /// Half the stroke's width, as a fraction of the photograph's longer side.
    public var radius: Double
    /// From each painted point to the point it copies, in the same fractions.
    public var offset: Point
    public init(points: [Point], radius: Double, offset: Point) {
        self.points=points;self.radius=min(0.25,max(0.002,radius.isFinite ? radius:0.02));self.offset=offset
    }
}
public struct DeviationRow: Equatable {
    public let id: UUID
    public let index: Int
    /// How far each measure is from what is usual in this project, in robust standard deviations.
    public var size: Double
    public var shape: Double
    public var taper: Double
    public var skew: Double
    public var worst: Double {max(size,shape,taper,skew)}
    public var isOutlier: Bool {worst>=Deviation.threshold}
    /// The measure that makes this page unusual, if any.
    public var reason: String? {
        guard isOutlier else {return nil}
        return [("size",size),("shape",shape),("taper",taper),("skew",skew)].max{$0.1<$1.1}?.0
    }
}
/// Finds pages whose crop is unlike the rest, as ScanTailor's deviation ordering does for skew, size and margins.
public enum Deviation {
    public enum Metric {case page, size, shape, taper, skew, worst}
    public static let threshold = 3.5
    /// Distance from the median in units of the median absolute deviation. Missing values and small groups score 0.
    public static func robustScores(_ values: [Double?], floor: Double) -> [Double] {
        let known=values.compactMap{$0}.sorted()
        guard known.count>=5 else {return values.map{_ in 0}}
        let median=known[known.count/2]
        let spread=known.map{abs($0-median)}.sorted()[known.count/2]/0.6745
        let scale=max(spread,floor)
        return values.map{$0.map{abs($0-median)/scale} ?? 0}
    }
    public static func report(_ pages: [Page]) -> [DeviationRow] {
        func sides(_ page: Page) -> [Double]? {
            guard let aspect=page.imageAspectRatio,page.quad.points.count == 4 else {return nil}
            let p=page.quad.points.map{CGPoint(x:$0.x*aspect,y:$0.y)}
            return (0..<4).map{hypot(p[$0].x-p[($0+1)%4].x,p[$0].y-p[($0+1)%4].y)}
        }
        let all=pages.map(sides)
        let size=robustScores(zip(pages,all).map{$1 == nil ? nil:$0.quad.area},floor:0.01)
        let shape=robustScores(all.map{$0.map{log(max(1e-6,$0[0]+$0[2])/max(1e-6,$0[1]+$0[3]))}},floor:0.01)
        let taper=robustScores(all.map{$0.map{max(abs(log(max(1e-6,$0[0])/max(1e-6,$0[2]))),abs(log(max(1e-6,$0[1])/max(1e-6,$0[3]))))}},floor:0.01)
        let skew=robustScores(pages.map{$0.deskew.flatMap{$0.map{abs($0)}.max()}},floor:0.15)
        return pages.indices.map{DeviationRow(id:pages[$0].id,index:$0,size:size[$0],shape:shape[$0],taper:taper[$0],skew:skew[$0])}
    }
    public static func sorted(_ rows: [DeviationRow], by metric: Metric, descending: Bool) -> [DeviationRow] {
        func value(_ r: DeviationRow) -> Double {
            switch metric {case .page:return Double(r.index);case .size:return r.size;case .shape:return r.shape;case .taper:return r.taper;case .skew:return r.skew;case .worst:return r.worst}
        }
        // Ties keep page order whichever way the column is sorted.
        return rows.sorted{value($0) == value($1) ? $0.index<$1.index:(descending ? value($0)>value($1):value($0)<value($1))}
    }
    /// The next unusual page after `index`, wrapping round; nil when there is none.
    public static func nextOutlier(after index: Int, in rows: [DeviationRow]) -> Int? {
        let outliers=rows.filter{$0.isOutlier}.map{$0.index}.sorted()
        return outliers.first{$0>index} ?? outliers.first
    }
}

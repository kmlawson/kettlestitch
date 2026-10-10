import Foundation
import Vision
import CoreImage

/// Multi-pass proposals. Scores are ranking heuristics, never calibrated probabilities.
public final class Detector {
    public init() {}
    public func detect(_ image: CGImage) throws -> [Candidate] {
        var proposed: [(Quad,Double,String)] = []
        func append(_ results: [VNRectangleObservation], _ name: String) {
            for r in results {
                let q=Quad([r.topLeft,r.topRight,r.bottomRight,r.bottomLeft].map{Point(Double($0.x),1.0-Double($0.y))})
                if q.valid && q.area>0.12 {proposed.append((q,Double(r.confidence),name))}
            }
        }
        let doc=VNDetectDocumentSegmentationRequest()
        // A segmentation failure should not suppress the independent edge detector.
        if (try? VNImageRequestHandler(cgImage:image).perform([doc])) != nil {append(doc.results ?? [],"Document")}
        for pass in 0..<2 {
            var analysis=image
            if pass==1 {
                let ci=CIImage(cgImage:image).applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.7]).applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:1.2])
                if let enhanced=Imaging.context.createCGImage(ci,from:CIImage(cgImage:image).extent) {analysis=enhanced}
            }
            let request=VNDetectRectanglesRequest()
            request.maximumObservations=16;request.minimumConfidence=0.15
            request.minimumAspectRatio=0.25;request.maximumAspectRatio=1
            request.minimumSize=0.25;request.quadratureTolerance=40
            try VNImageRequestHandler(cgImage:analysis).perform([request])
            append(request.results ?? [],pass==0 ? "Edges" : "Enhanced edges")
        }
        let background=BackgroundBoundary(image)
        let material=BackgroundMaterial(image)
        if let (quad,support)=background.detect(material:material){proposed.append((quad,support,"Material boundary"))}
        for rank in 0..<4 {if let (quad,support)=background.detect(rank:rank){proposed.append((quad,support,"Background boundary"))}}
        let gray=Gray(image)
        var candidates: [Candidate]=[]
        for (q,confidence,source) in proposed {
            let refined=gray.refine(q)
            for (shape,label) in [(q,source),(refined,source+" refined")] {
                guard ProposalPolicy.accepts(shape, imageAspectRatio: Double(image.width)/Double(image.height)) else {continue}
                let edge=gray.support(shape)
                // Whole-photo/spread intent: favor broad coverage over interior print frames.
                let area=min(shape.area/0.8,1)
                let border=shape.points.filter{$0.x<0.006 || $0.x>0.994 || $0.y<0.006 || $0.y>0.994}.count
                let lengths=(0..<4).map{shape.points[$0].distance(shape.points[($0+1)%4])}
                let asymmetry=abs(log(max(0.001,lengths[0])/max(0.001,lengths[2])))+abs(log(max(0.001,lengths[1])/max(0.001,lengths[3])))
                let diagonal=(0..<4).map{ i -> Double in let a=shape.points[i],b=shape.points[(i+1)%4];return i%2==0 ? abs(b.y-a.y)/max(0.01,abs(b.x-a.x)):abs(b.x-a.x)/max(0.01,abs(b.y-a.y))}.max() ?? 0
                let shapePenalty=max(0,asymmetry-0.25)*0.25+max(0,diagonal-0.30)*0.35
                let bonus=["Background boundary","Material boundary"].contains(source) ? 0.14:source=="Document" ? 0.10:0.04
                let contamination=material.contamination(shape)
                let perspectivePenalty=ProposalPolicy.unevenPerspectivePenalty(shape,imageAspectRatio:Double(image.width)/Double(image.height))
                let materialPenalty=min(0.35,contamination*2.5)
                let score=0.58*area+0.20*edge+0.16*confidence+bonus-Double(border)*0.035-shapePenalty-materialPenalty-perspectivePenalty
                candidates.append(Candidate(quad:shape,score:score,source:label))
            }
        }
        candidates.sort{$0.score>$1.score}
        var unique: [Candidate]=[]
        for c in candidates where !unique.contains(where:{$0.quad.distance(c.quad)<0.012}) {unique.append(c)}
        return Array(unique.prefix(6))
    }
}
private struct Gray {
    let bytes: [UInt8]
    let w: Int
    let h: Int
    init(_ image: CGImage) {
        let w=image.width,h=image.height
        self.w=w;self.h=h
        var data=[UInt8](repeating:0,count:w*h)
        data.withUnsafeMutableBytes { buffer in
            if let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) {c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))}
        }
        bytes=data
    }
    func sample(_ p: Point) -> Double {
        let x=min(w-1,max(0,Int(p.x*Double(w)))), y=min(h-1,max(0,Int(p.y*Double(h))))
        return Double(bytes[y*w+x])/255
    }
    func edge(_ a: Point,_ b: Point) -> Double {
        let dx=(b.x-a.x)*Double(w),dy=(b.y-a.y)*Double(h), length=max(1,hypot(dx,dy))
        let nx = -dy/length/Double(w)*4, ny=dx/length/Double(h)*4
        var differences: [Double]=[]
        for i in 3..<38 {
            let t=Double(i)/40, p=Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)
            let inside=sample(Point(p.x+nx,p.y+ny)),outside=sample(Point(p.x-nx,p.y-ny))
            differences.append(max(0,inside-outside))
        }
        differences.sort()
        return min(1,differences[ differences.count/2 ]*5)
    }
    func support(_ q: Quad) -> Double {(0..<4).map{edge(q.points[$0],q.points[($0+1)%4])}.reduce(0,+)/4}
    func refine(_ q: Quad) -> Quad {
        // Translate each supporting line locally; intersect adjacent lines for independent corners.
        var lines: [(Point,Point)]=[]
        for i in 0..<4 {
            let a=q.points[i], b=q.points[(i+1)%4],dx=b.x-a.x,dy=b.y-a.y,len=max(0.001,hypot(dx,dy))
            var best=(a,b),bestScore=edge(a,b)
            for step in -6...6 {
                let offset=Double(step)*0.002
                let u=Point(a.x-dy/len*offset,a.y+dx/len*offset),v=Point(b.x-dy/len*offset,b.y+dx/len*offset)
                let score=edge(u,v)-abs(offset)*2
                if score>bestScore {best=(u,v);bestScore=score}
            }
            lines.append(best)
        }
        func intersection(_ l:(Point,Point),_ m:(Point,Point)) -> Point? {
            let a=l.0,b=l.1,c=m.0,d=m.1
            let rx=b.x-a.x,ry=b.y-a.y,sx=d.x-c.x,sy=d.y-c.y,den=rx*sy-ry*sx
            guard abs(den)>0.00001 else {return nil}
            let t=((c.x-a.x)*sy-(c.y-a.y)*sx)/den
            return Point(a.x+t*rx,a.y+t*ry)
        }
        let points=(0..<4).compactMap{intersection(lines[($0+3)%4],lines[$0])}
        let result=Quad(points)
        return result.valid ? result:q
    }
}

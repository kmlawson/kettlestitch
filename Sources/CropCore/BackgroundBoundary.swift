import CoreGraphics
import Foundation

/// Independent proposal from the dominant border color and robust outer supporting lines.
/// Intended to rescue illustrated spreads whose printed content confuses rectangle detectors.
struct BackgroundBoundary {
    struct RGB {
        var r:Double;var g:Double;var b:Double
        func distance(_ c:RGB)->Double {sqrt(pow(r-c.r,2)+pow(g-c.g,2)+pow(b-c.b,2))}
        var key:Int {Int(r*7)*64+Int(g*7)*8+Int(b*7)}
    }
    struct Line {var m:Double;var b:Double;var support:Double}
    let pixels:[UInt8]
    let w=400,h=300
    init(_ image:CGImage){
        var data=[UInt8](repeating:0,count:400*300*4)
        data.withUnsafeMutableBytes{buffer in if let c=CGContext(data:buffer.baseAddress,width:400,height:300,bitsPerComponent:8,bytesPerRow:1600,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue){c.draw(image,in:CGRect(x:0,y:0,width:400,height:300))}}
        pixels=data
    }
    func color(_ x:Double,_ y:Double)->RGB {let i=(min(h-1,max(0,Int(y*Double(h))))*w+min(w-1,max(0,Int(x*Double(w)))))*4;return RGB(r:Double(pixels[i])/255,g:Double(pixels[i+1])/255,b:Double(pixels[i+2])/255)}
    func detect(rank:Int=0,material:BackgroundMaterial?=nil)->(Quad,Double)? {
        var buckets:[Int:[RGB]]=[:]
        // Four corner patches supply the scene background without learning paper from the gutter.
        for yi in 0..<12 {for xi in 0..<12 {for (ox,oy) in [(0.0,0.0),(0.94,0.0),(0.0,0.94),(0.94,0.94)] {
            let c=color(ox+Double(xi)*0.005,oy+Double(yi)*0.005);buckets[c.key,default:[]].append(c)
        }}}
        let clusters=buckets.values.sorted{$0.count>$1.count}
        guard rank<clusters.count else{return nil}
        let cluster=clusters[rank]
        guard cluster.count>30 else{return nil}
        let background=RGB(r:cluster.map{$0.r}.reduce(0,+)/Double(cluster.count),g:cluster.map{$0.g}.reduce(0,+)/Double(cluster.count),b:cluster.map{$0.b}.reduce(0,+)/Double(cluster.count))
        let spread=cluster.map{$0.distance(background)}.sorted()[cluster.count*9/10]
        let threshold=max(0.14,spread*2.4)
        func foreground(_ x:Double,_ y:Double)->Bool{material.map{!$0.isBackground(x,y)} ?? (color(x,y).distance(background)>threshold)}
        var edges=[[(Double,Double)]](repeating:[],count:4)
        for i in 0..<70 {
            let t=0.12+Double(i)/69*0.76
            for edge in 0..<4 {
                for j in 1..<155 {
                    let s=Double(j)/400
                    func coords(_ d:Double)->(Double,Double){switch edge{case 0:return(t,d);case 1:return(1-d,t);case 2:return(t,1-d);default:return(d,t)}}
                    let p=coords(s)
                    if !foreground(p.0,p.1){continue}
                    var votes=0
                    for k in 1...10 {let q=coords(s+Double(k)*0.003);if foreground(q.0,q.1){votes+=1}}
                    if votes>=9 {let value=(edge==1 || edge==2) ? 1-s:s;edges[edge].append((t,value));break}
                }
            }
        }
        func fit(_ points:[(Double,Double)])->Line? {
            guard points.count>=25 else{return nil}
            var best:[(Double,Double)]=[],bestScore = -Double.infinity
            for i in stride(from:0,to:points.count,by:2) {for j in stride(from:i+10,to:points.count,by:3){
                let p=points[i],q=points[j],m=(q.1-p.1)/(q.0-p.0)
                guard abs(m)<0.45 else{continue};let b=p.1-m*p.0
                let inliers=points.filter{abs($0.1-(m*$0.0+b))<0.013}
                let score=Double(inliers.count)-abs(m)*3
                if score>bestScore{bestScore=score;best=inliers}
            }}
            guard best.count>=25 else{return nil}
            let n=Double(best.count),mx=best.map{$0.0}.reduce(0,+)/n,my=best.map{$0.1}.reduce(0,+)/n
            let denominator=best.map{pow($0.0-mx,2)}.reduce(0,+)
            guard denominator>0.001 else{return nil}
            let m=best.map{($0.0-mx)*($0.1-my)}.reduce(0,+)/denominator
            return Line(m:m,b:my-m*mx,support:n/70)
        }
        guard let top=fit(edges[0]),let right=fit(edges[1]),let bottom=fit(edges[2]),let left=fit(edges[3]) else{return nil}
        func intersection(_ horizontal:Line,_ vertical:Line)->Point{
            let y=(horizontal.m*vertical.b+horizontal.b)/(1-horizontal.m*vertical.m)
            return Point(vertical.m*y+vertical.b,y)
        }
        let corners=[intersection(top,left),intersection(top,right),intersection(bottom,right),intersection(bottom,left)]
        // Tight framing can put an extrapolated corner just outside the photograph.
        guard corners.allSatisfy({(-0.04...1.04).contains($0.x) && (-0.04...1.04).contains($0.y)}) else{return nil}
        let q=Quad(corners.map{Point(min(1,max(0,$0.x)),min(1,max(0,$0.y)))})
        guard q.valid,q.area>0.25 else{return nil}
        return(q,[top,right,bottom,left].map{$0.support}.reduce(0,+)/4)
    }
}

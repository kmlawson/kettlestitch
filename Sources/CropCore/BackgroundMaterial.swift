import Foundation
import CoreGraphics

/// Per-photo appearance model. Only border-connected matches count as background;
/// similar print in the middle of a page must not count as exposed tabletop.
struct BackgroundMaterial {
    struct Feature {
        var r:Double;var g:Double;var b:Double;var texture:Double
        func matches(_ other:Feature)->Bool {
            let color=hypot(hypot(r-other.r,g-other.g),b-other.b)
            return color < 0.105 && abs(texture-other.texture) < 0.045
        }
    }
    let width=100,height=75
    var background:[Bool]
    init(_ image:CGImage) {
        let raster=BackgroundBoundary(image)
        var features:[Feature]=[]
        for y in 0..<75 {for x in 0..<100 {
            var colors:[BackgroundBoundary.RGB]=[]
            for dy in -2...2 {for dx in -2...2 {
                colors.append(raster.color((Double(x)+0.5)/100+Double(dx)/400,(Double(y)+0.5)/75+Double(dy)/300))
            }}
            let r=colors.map{$0.r}.reduce(0,+)/25,g=colors.map{$0.g}.reduce(0,+)/25,b=colors.map{$0.b}.reduce(0,+)/25
            let mean=(r+g+b)/3
            let variance=colors.map{pow(($0.r+$0.g+$0.b)/3-mean,2)}.reduce(0,+)/25
            features.append(Feature(r:r,g:g,b:b,texture:sqrt(variance)))
        }}
        var cornerSamples:[(Int,Feature)]=[]
        for y in 0..<75 {for x in 0..<100 where (x<5 || x>=95) && (y<5 || y>=70) {
            cornerSamples.append(((y<5 ? 0:2)+(x<5 ? 0:1),features[y*100+x]))
        }}
        // Demand recurring material in two corners. A lone finger, book, or shadow
        // cannot become the learned tabletop merely by occupying one corner.
        let prototypes=cornerSamples.filter { seed in
            seed.1.texture > 0.025 && Set(cornerSamples.filter{seed.1.matches($0.1)}.map{$0.0}).count>=2
        }.map{$0.1}
        let matches=features.map{f in prototypes.contains{f.matches($0)}}
        func connected(_ mask:[Bool])->[Bool] {
            var result=[Bool](repeating:false,count:7500),queue:[Int]=[]
            for y in 0..<75 {for x in 0..<100 {
                let seed=x==0 || x==99 || y==0 || y==74
                let i=y*100+x
                if seed && mask[i] {result[i]=true;queue.append(i)}
            }}
            var head=0
            while head<queue.count {
                let i=queue[head];head+=1;let x=i%100,y=i/100
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && nx<100 && ny>=0 && ny<75 {
                    let j=ny*100+nx
                    if mask[j] && !result[j] {result[j]=true;queue.append(j)}
                }
            }
            return result
        }
        background=connected(matches)

    }
    func isBackground(_ x:Double,_ y:Double)->Bool {
        let col=min(99,max(0,Int(x*100))),row=min(74,max(0,Int(y*75)))
        return background[row*100+col]
    }
    func contamination(_ q:Quad)->Double {
        var total=0,bg=0
        for y in 0..<75 {for x in 0..<100 {
            let p=Point((Double(x)+0.5)/100,(Double(y)+0.5)/75)
            var inside=true
            for i in 0..<4 {
                let a=q.points[i],b=q.points[(i+1)%4]
                let cross:Double=(b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x)
                if cross<0 {inside=false;break}
            }
            if inside {total+=1;if background[y*100+x]{bg+=1}}
        }}
        return Double(bg)/Double(max(1,total))
    }
}

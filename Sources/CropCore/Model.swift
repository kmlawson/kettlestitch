import Foundation
import CoreGraphics

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public var cg: CGPoint { CGPoint(x: x, y: y) }
    public func distance(_ p: Point) -> Double { hypot(x-p.x, y-p.y) }
}
/// Clockwise, top-left origin, normalized against the EXIF-oriented original.
public struct Quad: Codable, Equatable {
    public var points: [Point]
    public init(_ points: [Point]) { self.points = points }
    public static let full = Quad([Point(0,0), Point(1,0), Point(1,1), Point(0,1)])
    public var area: Double {
        guard points.count == 4 else { return 0 }
        return abs((0..<4).reduce(0.0) { v,i in let a=points[i], b=points[(i+1)%4]; return v+a.x*b.y-b.x*a.y })/2
    }
    public var valid: Bool {
        guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }), area > 0.005 else { return false }
        return (0..<4).allSatisfy { i in
            let a=points[i], b=points[(i+1)%4], c=points[(i+2)%4]
            return (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) > 0.00001
        }
    }
    /// Uniform scaling about the corner centroid, limited by the image boundary.
    public func scaled(by factor: Double) -> Quad? {
        guard valid, factor.isFinite, factor > 0 else { return nil }
        let center=Point(points.map{$0.x}.reduce(0,+)/4,points.map{$0.y}.reduce(0,+)/4)
        var scale=factor
        if factor > 1 {
            for p in points {
                for (c,d) in [(center.x,p.x-center.x),(center.y,p.y-center.y)] {
                    if d > 0 { scale=min(scale,(1-c)/d) }
                    else if d < 0 { scale=min(scale,-c/d) }
                }
            }
        }
        let result=Quad(points.map{Point(min(1,max(0,center.x+($0.x-center.x)*scale)),min(1,max(0,center.y+($0.y-center.y)*scale)))})
        return result.valid ? result:nil
    }
    /// Resize from one corner while preserving all four supporting-line directions.
    public func movingCornerPreservingAngles(_ corner:Int,to target:Point)->Quad? {
        guard valid,(0..<4).contains(corner),target.x.isFinite,target.y.isFinite else{return nil}
        let previous=(corner+3)%4,next=(corner+1)%4,opposite=(corner+2)%4
        func intersection(_ a:Point,_ direction:Point,_ b:Point,_ other:Point)->Point? {
            let determinant=direction.x*other.y-direction.y*other.x
            guard abs(determinant)>1e-10 else{return nil}
            let t=((b.x-a.x)*other.y-(b.y-a.y)*other.x)/determinant
            return Point(a.x+t*direction.x,a.y+t*direction.y)
        }
        func vector(_ a:Point,_ b:Point)->Point {Point(b.x-a.x,b.y-a.y)}
        guard let p=intersection(target,vector(points[corner],points[previous]),points[opposite],vector(points[opposite],points[previous])),
              let n=intersection(target,vector(points[corner],points[next]),points[opposite],vector(points[opposite],points[next])) else{return nil}
        var result=self
        result.points[corner]=target;result.points[previous]=p;result.points[next]=n
        return result.valid ? result:nil
    }
    public func translated(by delta:Point)->Quad? {
        guard valid,delta.x.isFinite,delta.y.isFinite else{return nil}
        let dx=min(1-points.map{$0.x}.max()!,max(-points.map{$0.x}.min()!,delta.x))
        let dy=min(1-points.map{$0.y}.max()!,max(-points.map{$0.y}.min()!,delta.y))
        let result=Quad(points.map{Point($0.x+dx,$0.y+dy)})
        return result.valid ? result:nil
    }
    public func movingEdge(_ edge: Int, by delta: Point) -> Quad? {
        guard valid,(0..<4).contains(edge) else{return nil}
        let indexes=[edge,(edge+1)%4]
        let xs=indexes.map{points[$0].x},ys=indexes.map{points[$0].y}
        let dx=min(1-xs.max()!,max(-xs.min()!,delta.x))
        let dy=min(1-ys.max()!,max(-ys.min()!,delta.y))
        var result=self
        for i in indexes {result.points[i]=Point(points[i].x+dx,points[i].y+dy)}
        return result.valid ? result:nil
    }
    public func distance(_ q: Quad) -> Double { guard points.count==4 && q.points.count==4 else {return 1}; return zip(points,q.points).map{$0.distance($1)}.reduce(0,+)/4 }
}
public struct Candidate: Codable {
    public var quad: Quad
    public var score: Double
    public var source: String
    public init(quad: Quad, score: Double, source: String) {self.quad=quad;self.score=score;self.source=source}
}
public struct Page: Codable, Identifiable {
    public var id = UUID()
    public var path: String
    public var quad = Quad.full
    public var candidates: [Candidate] = []
    public var status = "Pending"
    public var reviewed = false
    public var rotation = 0
    public var revision = 0
    public var imageAspectRatio: Double?
    public init(path: String) {self.path=path;imageAspectRatio=Imaging.aspectRatio(URL(fileURLWithPath:path))}
    public mutating func filterProposals() {
        if imageAspectRatio == nil {imageAspectRatio=Imaging.aspectRatio(URL(fileURLWithPath:path))}
        // Missing sources cannot supply trustworthy pixel-space geometry.
        let ratio=imageAspectRatio
        let accepts: (Quad)->Bool = { q in
            guard let aspect=ratio else{return false}
            return ProposalPolicy.accepts(q,imageAspectRatio:aspect)
        }
        candidates.removeAll { !accepts($0.quad) }
        if !reviewed, ["Check proposal","Proposal selected"].contains(status), !accepts(quad) {
            quad=candidates.first?.quad ?? .full
            status=candidates.isEmpty ? "No suitable proposal — crop manually":"Check proposal"
            revision += 1
        }
    }
}
public struct Project: Codable {
    public var version = 1
    public var pages: [Page] = []
    public var selected = 0
    public init() {}
    public static func read(_ url: URL) throws -> Project {
        var p = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
        guard p.version == 1, p.pages.allSatisfy({$0.quad.valid && $0.candidates.allSatisfy{$0.quad.valid}}) else {throw CropError.message("Unsupported or invalid project geometry")}
        for i in p.pages.indices {p.pages[i].filterProposals()}
        return p
    }
    public func save(_ url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
public enum CropError: LocalizedError {
    case message(String)
    public var errorDescription: String? {if case .message(let m)=self {return m};return nil}
}

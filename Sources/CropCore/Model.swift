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
    /// Scaling about the corner centroid. A side that reaches the image boundary stops there; the others keep growing.
    public func scaled(by scale: Double) -> Quad? {
        guard valid, scale.isFinite, scale > 0 else { return nil }
        let center=Point(points.map{$0.x}.reduce(0,+)/4,points.map{$0.y}.reduce(0,+)/4)
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
    /// A fresh detection replaces the detector's earlier proposals but keeps Claude's.
    public static func merging(detected: [Candidate], into existing: [Candidate]) -> [Candidate] {
        ordered(detected+existing.filter{$0.source == claudeSource})
    }
    public static let claudeSource = "Claude"
    /// The highest-scoring proposal first, then the rest from largest to smallest.
    public static func ordered(_ candidates: [Candidate]) -> [Candidate] {
        guard let best=candidates.indices.max(by:{candidates[$0].score<candidates[$1].score}) else {return []}
        var rest=candidates;let first=rest.remove(at:best)
        return [first]+rest.sorted{$0.quad.area>$1.quad.area}
    }
}
public enum Cleanup: String, Codable, CaseIterable {
    case none, blackAndWhite, grayscale, color
    public var title: String {
        switch self {case .none:return "None";case .blackAndWhite:return "Black & White";case .grayscale:return "Grayscale";case .color:return "Color"}
    }
    /// Modes whose output has no colour.
    public var isMonochrome: Bool {self == .grayscale || self == .blackAndWhite}
}
/// Brightness and contrast are -1...1 with 0 neutral. Sharpness is 0...1.
public struct Adjustments: Codable, Equatable {
    public var cleanup = Cleanup.none
    public var brightness = 0.0
    public var contrast = 0.0
    /// Speck removal for black-and-white output: 1 cautious, 2 normal, 3 aggressive; nil is off.
    public var despeckle: Int?
    /// Optional so that projects written before it existed still decode; nil is off.
    public var sharpness: Double?
    public init() {}
    public var isIdentity: Bool {self == Adjustments()}
}
public enum PaperSize: String, Codable, CaseIterable {
    case a3, a4, a5, b5, letter, legal
    public var title: String {
        switch self {case .a3:return "A3";case .a4:return "A4";case .a5:return "A5";case .b5:return "B5";case .letter:return "US Letter";case .legal:return "US Legal"}
    }
    /// Portrait width and height in centimetres.
    public var centimetres: (Double, Double) {
        switch self {case .a3:return (29.7,42.0);case .a4:return (21.0,29.7);case .a5:return (14.8,21.0);case .b5:return (17.6,25.0);case .letter:return (21.59,27.94);case .legal:return (21.59,35.56)}
    }
}
/// Physical size of the corrected output. Height follows the crop's aspect ratio.
public struct PageFormat: Codable, Equatable {
    public var widthCM: Double?
    public var fitInto: PaperSize?
    public init(widthCM: Double? = nil, fitInto: PaperSize? = nil) {self.widthCM=widthCM;self.fitInto=fitInto}
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
    // Optional so that version 1 projects written before these existed still decode.
    public var adjustments: Adjustments?
    public var format: PageFormat?
    public var flagged: Bool?
    public var split: PageSplit?
    /// Degrees each output part is turned clockwise as seen: one value for the whole crop, or left then right page.
    public var deskew: [Double]?
    public var pictureZones: [PictureZone]?
    /// Claude's latest comment on this crop.
    public var reviewNote: String?
    public init(path: String) {self.path=path;imageAspectRatio=Imaging.aspectRatio(URL(fileURLWithPath:path))}
    public func deskewAngle(part: Int, of count: Int) -> Double {
        guard let deskew,deskew.count == count,deskew.indices.contains(part) else {return 0}
        return deskew[part]
    }
    /// Turns every part by `delta` degrees. A list for a different number of parts starts again from level.
    public static func nudged(_ current: [Double]?, by delta: Double, parts: Int) -> [Double]? {
        let base=current?.count == parts ? current!:[Double](repeating:0,count:parts)
        let result=base.map{((min(SkewDetector.limit,max(-SkewDetector.limit,$0+delta)))*10000).rounded()/10000}
        return result.allSatisfy{abs($0)<1e-9} ? nil:result
    }
    /// A crop set by hand. Claude's comment described the crop it replaces, so it goes.
    public mutating func setManualCrop(_ q: Quad) {quad=q;status="Manual";reviewed=false;reviewNote=nil}
    public mutating func selectProposal(_ q: Quad) {quad=q;status="Proposal selected";reviewed=false}
    /// Stores Claude's verdict on the crop that was sent. Returns false, changing nothing, if the crop has been edited since.
    /// A moved split line is applied, provided the line is still the one that was sent.
    @discardableResult public mutating func record(_ review: CropReview, sentQuad: Quad, sentSplit: PageSplit? = nil) -> Bool {
        guard quad == sentQuad else {return false}
        let moved=review.split != nil && split != nil && split == sentSplit
        if moved {split=review.split}
        candidates.removeAll{$0.source == Candidate.claudeSource}
        if let fix=review.quad {candidates=Candidate.ordered(candidates+[Candidate(quad:fix,score:0,source:Candidate.claudeSource)])}
        let verdict=(review.quad != nil ? "Claude proposes a fix":review.good ? "Claude: crop looks right":"Claude: no usable fix")+(moved ? "; split line moved":"")
        reviewNote=review.comment.isEmpty ? verdict:verdict+" — "+review.comment
        return true
    }
    public mutating func filterProposals() {
        if imageAspectRatio == nil {imageAspectRatio=Imaging.aspectRatio(URL(fileURLWithPath:path))}
        // Missing sources cannot supply trustworthy pixel-space geometry.
        let ratio=imageAspectRatio
        let accepts: (Quad)->Bool = { q in
            guard let aspect=ratio else{return false}
            return ProposalPolicy.accepts(q,imageAspectRatio:aspect)
        }
        // The limits describe what the detector may propose. Claude's proposal was asked for and is kept as given.
        candidates.removeAll { $0.source != Candidate.claudeSource && !accepts($0.quad) }
        candidates=Candidate.ordered(candidates)
        let fromClaude=candidates.contains{$0.source == Candidate.claudeSource && $0.quad == quad}
        if !reviewed, !fromClaude, ["Check proposal","Proposal selected"].contains(status), !accepts(quad) {
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
    /// Undoes or redoes a change to the page list. The snapshot decides which pages exist and in what order;
    /// each surviving page keeps whatever has been done to it since.
    public static func restoringStructure(_ snapshot: [Page], current: [Page]) -> [Page] {
        var latest:[UUID:Page]=[:]
        for page in current {latest[page.id]=page}
        return snapshot.map{latest[$0.id] ?? $0}
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

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
    /// A fresh detection replaces the detector's earlier proposals but keeps a reviewer's.
    public static func merging(detected: [Candidate], into existing: [Candidate]) -> [Candidate] {
        ordered(detected+existing.filter{$0.isReview})
    }
    public static let claudeSource = "Claude"
    /// True for a crop that Claude or another provider's model proposed, which is named after it.
    public var isReview: Bool {ReviewProvider.allCases.contains{$0.name == source}}
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
/// Brightness, contrast and exposure are -1...1 with 0 neutral. Sharpness is 0...1.
public struct Adjustments: Codable, Equatable {
    public var cleanup = Cleanup.none
    public var brightness = 0.0
    public var contrast = 0.0
    /// Speck removal for black-and-white output: 1 cautious, 2 normal, 3 aggressive; nil is off.
    public var despeckle: Int?
    /// Optional so that projects written before it existed still decode; nil is off.
    public var sharpness: Double?
    /// -1...1 with 0 neutral, two stops either way. Optional for the same reason; nil is neutral.
    public var exposure: Double?
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
    /// True once the user has placed the split: dragged it, moved it with the keys or chosen another candidate.
    public var splitByHand: Bool?
    public var smudges: [Smudge]?
    public var clones: [CloneStroke]?
    /// Claude's latest comment on this crop.
    public var reviewNote: String?
    public init(path: String) {self.path=path;imageAspectRatio=Imaging.aspectRatio(URL(fileURLWithPath:path))}
    public func deskewAngle(part: Int, of count: Int) -> Double {
        guard let deskew,deskew.count == count,deskew.indices.contains(part) else {return 0}
        return deskew[part]
    }
    /// True when a split proposal worked out for this page as it was may still be given to the page as it is `now`.
    /// Anything the user did to the crop, the turn or the split meanwhile, Undo included, makes the proposal stale.
    public func splitResultApplies(to now: Page) -> Bool {
        now.id == id && now.quad == quad && now.rotation == rotation && now.revision == revision && now.split == split && now.splitByHand == splitByHand
    }
    /// The same for a measured tilt, which a deskew set or removed by hand also makes stale.
    public func deskewResultApplies(to now: Page) -> Bool {
        now.id == id && now.quad == quad && now.rotation == rotation && now.revision == revision && now.split == split && now.deskew == deskew
    }
    /// The deskew after the page is turned by quarter turns. One page keeps its tilt; the two pages of a spread
    /// change places on a half turn, and on a quarter turn are no longer the pages that were measured.
    public static func deskew(_ current: [Double]?, afterQuarterTurns turns: Int, parts: Int) -> [Double]? {
        guard let current,current.count == parts else {return nil}
        let turn=((turns%4)+4)%4
        if parts == 1 || turn == 0 {return current}
        return turn == 2 ? Array(current.reversed()):nil
    }
    /// The deskew if it is for this many output pages, and otherwise none.
    public static func deskew(_ current: [Double]?, fitting parts: Int) -> [Double]? {current?.count == parts ? current:nil}
    /// Turns every part by `delta` degrees, or just part `only`. A list for a different number of parts starts again from level.
    public static func nudged(_ current: [Double]?, by delta: Double, parts: Int, only: Int? = nil) -> [Double]? {
        let base=current?.count == parts ? current!:[Double](repeating:0,count:parts)
        let result=base.enumerated().map{only == nil || only == $0.offset ? ((min(SkewDetector.limit,max(-SkewDetector.limit,$0.element+delta)))*10000).rounded()/10000:$0.element}
        return result.allSatisfy{abs($0)<1e-9} ? nil:result
    }
    /// The deskew after `measured` replaces it: for every part, or for part `only` with the others kept. No
    /// measurement means level.
    public static func deskew(_ current: [Double]?, setting measured: [Double]?, parts: Int, only: Int?) -> [Double]? {
        guard let only else {return measured}
        var result=current?.count == parts ? current!:[Double](repeating:0,count:parts)
        guard result.indices.contains(only) else {return current}
        result[only]=measured?.count == parts ? measured![only]:0
        return result.allSatisfy{abs($0)<1e-9} ? nil:result
    }
    /// A crop set by hand. Claude's comment described the crop it replaces, so it goes.
    public mutating func setManualCrop(_ q: Quad) {quad=q;status="Manual";reviewed=false;reviewNote=nil}
    public mutating func selectProposal(_ q: Quad) {quad=q;status="Proposal selected";reviewed=false}
    /// Stores Claude's verdict on the crop that was sent and selects its fix, if it made one. Returns false, changing nothing, if the crop has been edited since.
    /// A moved split line is applied, provided the line is still the one that was sent.
    /// `reviewer` is what the model that answered is called: Claude, OpenAI or Gemini.
    /// A page turned since it was sent is left alone too: the same numbers then mean another place.
    @discardableResult public mutating func record(_ review: CropReview, sentQuad: Quad, sentSplit: PageSplit? = nil, sentRotation: Int? = nil, reviewer: String = Candidate.claudeSource) -> Bool {
        guard quad == sentQuad,sentRotation == nil || rotation == sentRotation else {return false}
        let moved=review.split != nil && split != nil && split == sentSplit
        if moved {split=review.split}
        candidates.removeAll{$0.isReview}
        // The reviewer's crop is selected at once and stays in the list; the crop it replaces is one Undo away.
        if let fix=review.quad {candidates=Candidate.ordered(candidates+[Candidate(quad:fix,score:0,source:reviewer)]);selectProposal(fix);revision+=1}
        let verdict=(review.quad != nil ? "\(reviewer)'s fix selected":review.good ? "\(reviewer): crop looks right":"\(reviewer): no usable fix")+(moved ? "; split line moved":"")
        reviewNote=review.comment.isEmpty ? verdict:verdict+" — "+review.comment
        return true
    }
    /// Brings everything a project file says about the page within what the app itself would write. A value that
    /// can only mean one thing is put right; a number that cannot be a place on a photograph is refused.
    mutating func normalize() throws {
        let name=URL(fileURLWithPath:path).lastPathComponent
        func refuse(_ what: String) -> CropError {.message("\(name): the project file gives \(what) that cannot be right, so it was not opened.")}
        func plausible(_ values: [Double]) -> Bool {values.allSatisfy{$0.isFinite && abs($0)<=1000}}
        func unit(_ v: Double, _ low: Double = -1) -> Double {v.isFinite ? min(1,max(low,v)):0}
        rotation=((rotation%4)+4)%4;revision=max(0,revision)
        if let ratio=imageAspectRatio,!(ratio.isFinite && ratio>0) {imageAspectRatio=nil}
        if let s=split {split=s.clamped}
        if let angles=deskew {
            guard plausible(angles) else {throw refuse("a deskew")}
            deskew=angles.count == 1 || angles.count == 2 ? angles.map{min(SkewDetector.limit,max(-SkewDetector.limit,$0))}:nil
        }
        if var a=adjustments {
            a.brightness=unit(a.brightness);a.contrast=unit(a.contrast);a.exposure=a.exposure.map{unit($0)};a.sharpness=a.sharpness.map{unit($0,0)}
            a.despeckle=a.despeckle.flatMap{$0<1 ? nil:min(3,$0)}
            adjustments=a
        }
        if let width=format?.widthCM {
            guard plausible([width]) else {throw refuse("a page width")}
            if width<=0 {format?.widthCM=nil}
        }
        if let zones=pictureZones {
            guard plausible(zones.flatMap{[$0.minU,$0.minV,$0.maxU,$0.maxV]}) else {throw refuse("a picture zone")}
            pictureZones=zones.map{PictureZone(from:($0.minU,$0.minV),to:($0.maxU,$0.maxV))}
        }
        if let strokes=smudges {
            guard plausible(strokes.flatMap{$0.points.flatMap{[$0.x,$0.y]}}) else {throw refuse("a smudge")}
            let kept=strokes.filter{!$0.points.isEmpty}.map{Smudge(points:$0.points,radius:$0.radius,strength:$0.strength,grain:$0.grain)}
            smudges=kept.isEmpty ? nil:kept
        }
        if let strokes=clones {
            guard plausible(strokes.flatMap{$0.points.flatMap{[$0.x,$0.y]}+[$0.offset.x,$0.offset.y]}) else {throw refuse("a cloned area")}
            let kept=strokes.filter{!$0.points.isEmpty}.map{CloneStroke(points:$0.points,radius:$0.radius,offset:$0.offset)}
            clones=kept.isEmpty ? nil:kept
        }
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
        candidates.removeAll { !$0.isReview && !accepts($0.quad) }
        candidates=Candidate.ordered(candidates)
        let fromClaude=candidates.contains{$0.isReview && $0.quad == quad}
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
        try JSONDecoder().decode(Project.self, from: Data(contentsOf: url)).checked()
    }
    /// The project as it may be opened: of a version this app reads, with sound geometry.
    public func checked() throws -> Project {
        var p=self
        guard p.version == 1, p.pages.allSatisfy({$0.quad.valid && $0.candidates.allSatisfy{$0.quad.valid}}) else {throw CropError.message("Unsupported or invalid project geometry")}
        guard Set(p.pages.map{$0.id}).count == p.pages.count else {throw CropError.message("This project lists the same page more than once under one identity, so it cannot be opened safely.")}
        for i in p.pages.indices {try p.pages[i].normalize();p.pages[i].filterProposals()}
        p.selected=min(max(0,p.selected),max(0,p.pages.count-1))
        return p
    }
    /// The page list after `rows` are taken out and put back together before row `destination`, both counted in the
    /// list as it stands. The moved pages keep their own order.
    public static func moving(_ pages: [Page], rows: IndexSet, to destination: Int) -> [Page] {
        let taken=rows.filter{pages.indices.contains($0)};guard !taken.isEmpty else {return pages}
        let moved=taken.map{pages[$0]},kept=pages.indices.filter{!taken.contains($0)}.map{pages[$0]}
        let place=min(max(0,destination),pages.count)
        // Rows above the place leave before it is reached, so it moves up by as many.
        let at=place-taken.filter{$0<place}.count
        return Array(kept[..<at])+moved+Array(kept[at...])
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

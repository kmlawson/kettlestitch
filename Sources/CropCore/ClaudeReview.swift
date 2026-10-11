import Foundation
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

/// What one request, or several added together, cost. Input counts every token read, cached or not.
public struct ReviewUsage: Codable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// In US dollars, as the tool reports it; nil when it did not.
    public var cost: Double?
    public init(inputTokens: Int = 0, outputTokens: Int = 0, cost: Double? = nil) {self.inputTokens=inputTokens;self.outputTokens=outputTokens;self.cost=cost}
    public static func + (a: ReviewUsage, b: ReviewUsage) -> ReviewUsage {
        ReviewUsage(inputTokens:a.inputTokens+b.inputTokens,outputTokens:a.outputTokens+b.outputTokens,cost:a.cost == nil && b.cost == nil ? nil:(a.cost ?? 0)+(b.cost ?? 0))
    }
    static func grouped(_ n: Int) -> String {
        let formatter=NumberFormatter();formatter.numberStyle = .decimal;formatter.locale=Locale(identifier:"en_US_POSIX");formatter.groupingSeparator=",";formatter.usesGroupingSeparator=true
        return formatter.string(from:NSNumber(value:n)) ?? String(n)
    }
    public var summary: String {
        "\(ReviewUsage.grouped(inputTokens)) tokens in, \(ReviewUsage.grouped(outputTokens)) out"+(cost.map{String(format:", $%.4f",$0)} ?? "")
    }
}
/// One request to Claude, as kept in the usage log.
public struct UsageEntry: Codable, Equatable {
    public var date: Date
    public var file: String
    public var model: String
    public var seconds: Double
    public var usage: ReviewUsage
    public init(date: Date, file: String, model: String, seconds: Double, usage: ReviewUsage) {self.date=date;self.file=file;self.model=model;self.seconds=seconds;self.usage=usage}
}
/// The history of requests, kept as JSON in the app's support folder. Nothing in it leaves the Mac.
public enum UsageLog {
    public static let fileName = "claude-usage.json"
    public static func read(_ url: URL) -> [UsageEntry] {
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageEntry].self,from:Data(contentsOf:url))) ?? []
    }
    public static func append(_ entry: UsageEntry, to url: URL) throws {
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601;encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(read(url)+[entry]).write(to:url,options:.atomic)
    }
    /// The log as text, newest request first, under a line of totals.
    public static func text(_ entries: [UsageEntry], timeZone: TimeZone = .current) -> String {
        guard !entries.isEmpty else {return "No requests have been sent yet."}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=timeZone;formatter.dateFormat="yyyy-MM-dd HH:mm:ss"
        let total=entries.reduce(ReviewUsage()){$0+$1.usage}
        let lines=entries.reversed().map{entry in
            "\(formatter.string(from:entry.date))  \(entry.model)  \(entry.file)  \(Int(entry.seconds.rounded())) s  \(entry.usage.summary)"
        }
        return "\(entries.count) request\(entries.count == 1 ? "":"s") in all: \(total.summary)\n\n"+lines.joined(separator:"\n")
    }
}
public struct CropReview: Equatable {
    public var good: Bool
    public var comment: String
    /// A corrected crop, or nil when the current one should stand.
    public var quad: Quad?
    /// A corrected line between the facing pages, or nil when there is none or the current one should stand.
    public var split: PageSplit? = nil
    /// Tokens and cost of the request, when the tool reported them.
    public var usage: ReviewUsage? = nil
}
/// What the interface shows while pages are with Claude.
public enum ReviewProgress {
    public enum State: Equatable {
        case queued, active
        public var label: String {self == .active ? "Waiting for an answer…":"Queued for review"}
    }
    public static func state(_ id: UUID, active: UUID?, pending: Set<UUID>) -> State? {
        id == active ? .active:pending.contains(id) ? .queued:nil
    }
    public static func status(model: String, number: Int, total: Int, name: String?, seconds: Int) -> String {
        var parts=["Waiting for \(model)"]
        if total>1,number>0 {parts.append("page \(number) of \(total)")}
        if let name {parts.append(name)}
        parts.append(seconds<60 ? "\(seconds) s":"\(seconds/60) min \(seconds%60) s")
        return parts.joined(separator:" · ")+" — Esc stops"
    }
}
/// Sends a reduced copy of a photograph and its crop to Claude, or another provider's model, for a second opinion.
/// The name is from when Claude was the only one; see `ReviewProvider` for the others.
public enum ClaudeReview {
    public static let photoName = "photo.jpg"
    public static let overlayName = "overlay.jpg"
    static let cornerKeys = ["top_left","top_right","bottom_right","bottom_left"]
    static let splitKeys = ["s1","s2"]
    /// `split` adds the two ends of the dividing line between facing pages to the answer.
    public static func schema(split: Bool = false) -> String {
        // Every object is closed and lists all its properties as required, which strict structured output asks for.
        func object(_ keys: [String], _ properties: String) -> String {
            "{\"type\":\"object\",\"properties\":{\(properties)},\"required\":[\(keys.map{"\"\($0)\""}.joined(separator:","))],\"additionalProperties\":false}"
        }
        let point=object(["x","y"],"\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"}")
        func points(_ keys: [String]) -> String {object(keys,keys.map{"\"\($0)\":\(point)"}.joined(separator:","))}
        let line=split ? ",\"split\":\(points(splitKeys))":""
        return object(["verdict","comment","corners"]+(split ? ["split"]:[]),"\"verdict\":{\"type\":\"string\",\"enum\":[\"good\",\"adjust\"]},\"comment\":{\"type\":\"string\"},\"corners\":\(points(cornerKeys))\(line)")
    }
    /// `split` is the dividing line's two ends on the photograph, when the page has one.
    public static func prompt(quad: Quad, split: (Point, Point)? = nil) -> String {
        let outline=split == nil ? "":" The line dividing the spread into its two pages is drawn in cyan, its ends labelled S1 and S2."
        let dividing=split.map{ends in """


        The spread is divided into its two pages along a line. Current line: s1 (x \(String(format:"%.4f",ends.0.x)), y \(String(format:"%.4f",ends.0.y))), s2 (x \(String(format:"%.4f",ends.1.x)), y \(String(format:"%.4f",ends.1.y))).

        A correct line runs along the fold between the two facing pages, the whole way across the spread from one edge of the crop to the opposite edge. A printed rule, the border of a printed frame or the edge of a column of text is not the fold, even where it is darker. If the line is within about half a percent of the fold along its whole length, return s1 and s2 unchanged. Otherwise return corrected coordinates, each end on the edge of the crop it is on now. The verdict is about the corners only.
        """} ?? ""
        let current=zip(cornerKeys,quad.points).map{String(format:"%@ (x %.4f, y %.4f)",$0,$1.x,$1.y)}.joined(separator:", ")
        return """
        You are checking the crop of a photograph of a printed book page or two-page spread.

        Two images are attached:
        - The first is the photograph.
        - The second is the same photograph with the current crop drawn as a magenta outline, its corners labelled TL, TR, BR and BL, and a faint grid whose lines are labelled in the coordinate system below.\(outline)

        Coordinates are fractions of the image width and height from 0 to 1. The origin is the top-left corner, x increases to the right and y increases downward.

        Current crop: \(current).

        A correct crop follows the outer boundary of the whole book or spread, including every visible page, as tightly as possible. It leaves out the table or background and never cuts into the paper. Do not shrink it to one page of a spread. Fingers holding the book may overlap the boundary; place the corner where the paper corner is or would be.

        Judge each corner separately. If every corner is within about one percent of the right place, the verdict is "good" and the corners are returned unchanged. Otherwise the verdict is "adjust", with corrected coordinates for only the corners that are wrong and the others exactly as given.\(dividing)

        Answer in this fixed format and nothing more. Do not describe the page or explain your reasoning.
        - "verdict": "good" or "adjust".
        - "corners": all four corners.\(split == nil ? "":"\n- \"split\": s1 and s2.")
        - "comment": at most ten words naming only what you moved, such as "TL, BR moved out"\(split == nil ? "":" or \"split moved right\""); "ok" if you moved nothing.
        """
    }
    public static func arguments(model: String, prompt: String, split: Bool = false) -> [String] {
        ["-p",prompt,"--bare","--model",model,"--tools","Read","--output-format","json","--json-schema",schema(split:split),"--no-session-persistence"]
    }
    /// Reads the model's answer, which is JSON in the agreed form. Unchanged or invalid coordinates produce no proposal.
    /// With `split` and `rotation`, the dividing line is read too and expressed across the crop that results,
    /// so it stays on the same place in the photograph when the corners move.
    public static func parse(_ text: String, current: Quad, split: PageSplit? = nil, rotation: Int = 0) throws -> CropReview {
        var answer=try? JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any]
        // A model that wraps the JSON in a sentence is still understood.
        if answer == nil,let start=text.firstIndex(of:"{"),let end=text.lastIndex(of:"}"),start<end {
            answer=try? JSONSerialization.jsonObject(with:Data(text[start...end].utf8)) as? [String:Any]
        }
        guard let answer,let verdict=answer["verdict"] as? String else {throw CropError.message("The answer had no verdict: "+String(text.prefix(300)))}
        let comment=(answer["comment"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        var quad:Quad?
        if let corners=answer["corners"] as? [String:Any] {
            let points=cornerKeys.compactMap{key->Point? in
                guard let corner=corners[key] as? [String:Any],let x=(corner["x"] as? NSNumber)?.doubleValue,let y=(corner["y"] as? NSNumber)?.doubleValue else {return nil}
                return Point(min(1,max(0,x)),min(1,max(0,y)))
            }
            if points.count == 4 {let proposed=Quad(points);if proposed.valid,proposed.distance(current)>0.002 {quad=proposed}}
        }
        let good=verdict == "good",final=good ? current:quad ?? current
        var moved:PageSplit?
        if let split,let line=answer["split"] as? [String:Any] {
            let ends=splitKeys.compactMap{key->(u:Double,v:Double)? in
                guard let end=line[key] as? [String:Any],let x=(end["x"] as? NSNumber)?.doubleValue,let y=(end["y"] as? NSNumber)?.doubleValue else {return nil}
                return SplitGeometry.position(of:Point(x,y),quad:final,rotation:rotation)
            }
            // The ends need not lie exactly on the crop's edges; the line through them is carried to both.
            if ends.count == 2,abs(ends[1].v-ends[0].v)>0.2 {
                let slope=(ends[1].u-ends[0].u)/(ends[1].v-ends[0].v)
                let line=PageSplit(top:ends[0].u-slope*ends[0].v,bottom:ends[0].u+slope*(1-ends[0].v))
                if line.top.isFinite,line.bottom.isFinite,max(abs(line.top-split.top),abs(line.bottom-split.bottom))>0.003 {moved=line.clamped}
            }
        }
        return CropReview(good:good,comment:comment,quad:good ? nil:quad,split:moved)
    }
    /// The photograph with the crop outline, corner labels and a labelled coordinate grid.
    public static func overlay(_ image: CGImage, quad: Quad, split: (Point, Point)? = nil) throws -> CGImage {
        let w=image.width,h=image.height
        guard let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw CropError.message("Could not draw crop overlay")}
        let width=CGFloat(w),height=CGFloat(h),unit=max(width,height)
        c.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        func place(_ p: Point) -> CGPoint {CGPoint(x:p.x*width,y:(1-p.y)*height)}
        func label(_ string: String, at point: CGPoint, color: CGColor) {
            let font=CTFontCreateWithName("Helvetica-Bold" as CFString,unit*0.018,nil)
            let line=CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):color]))
            // Image bounds are relative to the text position, which each draw advances.
            c.textPosition = .zero
            let bounds=CTLineGetImageBounds(line,c)
            let origin=CGPoint(x:min(max(4,point.x),width-bounds.width-8),y:min(max(4,point.y),height-bounds.height-8))
            c.setFillColor(CGColor(gray:0,alpha:0.6));c.fill(CGRect(x:origin.x-3,y:origin.y-3,width:bounds.width+6,height:bounds.height+6))
            c.textPosition=CGPoint(x:origin.x-bounds.minX,y:origin.y-bounds.minY);CTLineDraw(line,c)
        }
        let yellow=CGColor(red:1,green:0.9,blue:0.2,alpha:1),magenta=CGColor(red:1,green:0,blue:1,alpha:1)
        c.setStrokeColor(CGColor(red:1,green:0.9,blue:0.2,alpha:0.45));c.setLineWidth(max(1,unit*0.001))
        for step in 1..<10 {
            let f=CGFloat(step)/10
            c.move(to:CGPoint(x:f*width,y:0));c.addLine(to:CGPoint(x:f*width,y:height))
            c.move(to:CGPoint(x:0,y:(1-f)*height));c.addLine(to:CGPoint(x:width,y:(1-f)*height))
        }
        c.strokePath()
        for step in 1..<10 {
            let f=CGFloat(step)/10,text=String(format:"%.1f",Double(step)/10)
            label("x "+text,at:CGPoint(x:f*width+4,y:height),color:yellow)
            label("y "+text,at:CGPoint(x:0,y:(1-f)*height+4),color:yellow)
        }
        c.setStrokeColor(magenta);c.setLineWidth(max(2,unit*0.003))
        c.move(to:place(quad.points[0]));for p in quad.points.dropFirst() {c.addLine(to:place(p))};c.closePath();c.strokePath()
        let inset=unit*0.012
        for (i,name) in ["TL","TR","BR","BL"].enumerated() {
            let p=place(quad.points[i])
            c.setFillColor(magenta);c.fillEllipse(in:CGRect(x:p.x-unit*0.006,y:p.y-unit*0.006,width:unit*0.012,height:unit*0.012))
            // Labels sit inside the crop so they never hide the boundary being judged.
            label(name,at:CGPoint(x:p.x+(i == 0 || i == 3 ? inset:-inset*4),y:p.y+(i < 2 ? -inset*3:inset)),color:magenta)
        }
        if let split {
            let cyan=CGColor(red:0,green:0.9,blue:1,alpha:1),a=place(split.0),b=place(split.1)
            c.setStrokeColor(cyan);c.setLineWidth(max(2,unit*0.002));c.move(to:a);c.addLine(to:b);c.strokePath()
            // Beside the line, so the fold under it stays visible.
            for (name,p) in [("S1",a),("S2",b)] {label(name,at:CGPoint(x:p.x+inset,y:p.y+(p.y>height/2 ? -inset*3:inset)),color:cyan)}
        }
        guard let result=c.makeImage() else {throw CropError.message("Could not draw crop overlay")}
        return result
    }
    /// The page's dividing line on the photograph, if it has one.
    public static func splitEnds(_ page: Page) -> (Point, Point)? {page.split.flatMap{SplitGeometry.line($0,quad:page.quad,rotation:page.rotation)}}
    /// The two reduced JPEGs that are sent: the photograph, and the same with the crop and split drawn on it.
    /// The original photograph is not altered or sent at full size.
    public static func images(for page: Page) throws -> (photo: Data, overlay: Data) {
        let photo=try Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1568)
        return (try Exporter.encode(photo,as:.jpeg,quality:0.82,dpi:nil),try Exporter.encode(overlay(photo,quad:page.quad,split:splitEnds(page)),as:.jpeg,quality:0.82,dpi:nil))
    }
    /// Writes those two images to a folder, to inspect what would be sent.
    public static func prepare(_ page: Page, in directory: URL) throws {
        let sent=try images(for:page)
        try sent.photo.write(to:directory.appendingPathComponent(photoName));try sent.overlay.write(to:directory.appendingPathComponent(overlayName))
    }
    /// Blocks until the model answers. `started` receives each request as it is made, so the caller can cancel it.
    /// A request that fails for a passing reason, such as too many at once, is tried up to three times.
    public static func run(_ page: Page, model: ReviewModel, apiKey: String, timeout: TimeInterval = 240, session: URLSession = ReviewAPI.session, started: (URLSessionTask) -> Void = {_ in}) throws -> CropReview {
        let sent=try images(for:page),ends=splitEnds(page)
        let request=try ReviewAPI.request(model:model,apiKey:apiKey,prompt:prompt(quad:page.quad,split:ends),photo:sent.photo,overlay:sent.overlay,split:ends != nil,timeout:timeout)
        var attempt=0
        while true {
            attempt+=1
            var reply:(data:Data?,response:URLResponse?,error:Error?)=(nil,nil,nil)
            let done=DispatchSemaphore(value:0)
            let task=session.dataTask(with:request){data,response,error in reply=(data,response,error);done.signal()}
            started(task);task.resume();done.wait()
            if let error=reply.error as? URLError {
                switch error.code {
                case .cancelled:throw CropError.message("\(model.provider.name) was stopped before it answered")
                case .timedOut:throw CropError.message("\(model.provider.name) did not answer within \(max(1,Int((timeout/60).rounded()))) minutes")
                default:throw CropError.message("Could not reach \(model.provider.name): \(error.localizedDescription)")
                }
            }
            if let error=reply.error {throw error}
            let http=reply.response as? HTTPURLResponse,status=http?.statusCode ?? 0
            if ReviewAPI.isTemporary(status:status),attempt<3 {
                // The service may say how long to wait; otherwise a little longer each time.
                let asked=http?.value(forHTTPHeaderField:"retry-after").flatMap(Double.init)
                Thread.sleep(forTimeInterval:min(30,asked ?? Double(attempt*attempt)*2));continue
            }
            let answer=try ReviewAPI.answer(reply.data ?? Data(),status:status,provider:model.provider)
            var review=try parse(answer.text,current:page.quad,split:ends == nil ? nil:page.split,rotation:page.rotation)
            if var usage=answer.usage {usage.cost=model.cost(usage);review.usage=usage}
            return review
        }
    }
}

import Foundation
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

public struct CropReview: Equatable {
    public var good: Bool
    public var comment: String
    /// A corrected crop, or nil when the current one should stand.
    public var quad: Quad?
    /// A corrected line between the facing pages, or nil when there is none or the current one should stand.
    public var split: PageSplit? = nil
}
/// What the interface shows while pages are with Claude.
public enum ReviewProgress {
    public enum State: Equatable {
        case queued, active
        public var label: String {self == .active ? "Waiting for Claude…":"Queued for Claude"}
    }
    public static func state(_ id: UUID, active: UUID?, pending: Set<UUID>) -> State? {
        id == active ? .active:pending.contains(id) ? .queued:nil
    }
    public static func status(model: String, number: Int, total: Int, name: String?, seconds: Int) -> String {
        var parts=["Waiting for Claude \(model)"]
        if total>1,number>0 {parts.append("page \(number) of \(total)")}
        if let name {parts.append(name)}
        parts.append(seconds<60 ? "\(seconds) s":"\(seconds/60) min \(seconds%60) s")
        return parts.joined(separator:" · ")+" — Esc stops"
    }
}
private final class TimedOut {var value=false}
/// Sends a reduced copy of a photograph and its crop to the `claude` command-line tool for a second opinion.
public enum ClaudeReview {
    public static let models: [(title: String, id: String)] = [("Haiku 5.5","claude-haiku-5-5"),("Sonnet 5.5","claude-sonnet-5-5")]
    public static let photoName = "photo.jpg"
    public static let overlayName = "overlay.jpg"
    static let cornerKeys = ["top_left","top_right","bottom_right","bottom_left"]
    static let splitKeys = ["s1","s2"]
    /// `split` adds the two ends of the dividing line between facing pages to the answer.
    public static func schema(split: Bool = false) -> String {
        let corner="{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"}},\"required\":[\"x\",\"y\"]}"
        let corners=cornerKeys.map{"\"\($0)\":\(corner)"}.joined(separator:",")
        let required=cornerKeys.map{"\"\($0)\""}.joined(separator:",")
        let line=split ? ",\"split\":{\"type\":\"object\",\"properties\":{\(splitKeys.map{"\"\($0)\":\(corner)"}.joined(separator:","))},\"required\":[\(splitKeys.map{"\"\($0)\""}.joined(separator:","))]}":""
        return "{\"type\":\"object\",\"properties\":{\"verdict\":{\"type\":\"string\",\"enum\":[\"good\",\"adjust\"]},\"comment\":{\"type\":\"string\"},\"corners\":{\"type\":\"object\",\"properties\":{\(corners)},\"required\":[\(required)]}\(line)},\"required\":[\"verdict\",\"comment\",\"corners\"\(split ? ",\"split\"":"")]}"
    }
    /// `split` is the dividing line's two ends on the photograph, when the page has one.
    public static func prompt(quad: Quad, split: (Point, Point)? = nil) -> String {
        let outline=split == nil ? "":" The line dividing the spread into its two pages is drawn in cyan, its ends labelled S1 and S2."
        let dividing=split.map{ends in """


        The spread will be divided into its two pages along a line. Current line: s1 (x \(String(format:"%.4f",ends.0.x)), y \(String(format:"%.4f",ends.0.y))), s2 (x \(String(format:"%.4f",ends.1.x)), y \(String(format:"%.4f",ends.1.y))).

        A correct line runs along the fold between the two facing pages, the whole way across the spread from one edge of the crop to the opposite edge. A printed rule, the border of a printed frame or the edge of a column of text is not the fold, even where it is darker than the fold. If the line is within about half a percent of the fold along its whole length, return s1 and s2 unchanged in "split". Otherwise return corrected coordinates for them, each on the edge of the crop it is on now, and say so in "comment". The verdict is about the crop's corners only.
        """} ?? ""
        let current=zip(cornerKeys,quad.points).map{String(format:"%@ (x %.4f, y %.4f)",$0,$1.x,$1.y)}.joined(separator:", ")
        return """
        You are checking the crop of a photograph of a printed book page or two-page spread.

        Use the Read tool on two files in the current directory:
        - \(photoName): the photograph.
        - \(overlayName): the same photograph with the current crop drawn as a magenta outline, its corners labelled TL, TR, BR and BL, and a faint grid whose lines are labelled in the coordinate system below.\(outline)

        Coordinates are fractions of the image width and height from 0 to 1. The origin is the top-left corner, x increases to the right and y increases downward.

        Current crop: \(current).

        A correct crop follows the outer boundary of the whole book or spread, including every visible page, as tightly as possible. It leaves out the table or background and never cuts into the paper. Do not split the spread into separate pages. Fingers holding the book may overlap the boundary; place the corner where the paper corner is or would be.

        Judge each corner separately. If every corner is within about one percent of the right place, answer with verdict "good" and return the corners unchanged. Otherwise answer with verdict "adjust", give corrected coordinates for only the corners that are wrong, and return the others exactly as given. In "comment", say in one or two sentences which corners you moved and why, or why the crop is already right.\(dividing)
        """
    }
    public static func arguments(model: String, prompt: String, split: Bool = false) -> [String] {
        ["-p",prompt,"--bare","--model",model,"--tools","Read","--output-format","json","--json-schema",schema(split:split),"--no-session-persistence"]
    }
    /// Reads the tool's JSON result. Unchanged or invalid coordinates produce no proposal.
    /// With `split` and `rotation`, a moved dividing line is read too and expressed across the current crop.
    public static func parse(_ output: Data, current: Quad, split: PageSplit? = nil, rotation: Int = 0) throws -> CropReview {
        guard let root=try? JSONSerialization.jsonObject(with:output) as? [String:Any] else {
            throw CropError.message("Claude returned an unreadable reply: "+String(decoding:output.prefix(300),as:UTF8.self))
        }
        let text=root["result"] as? String ?? ""
        if root["is_error"] as? Bool == true {throw CropError.message(text.isEmpty ? "Claude reported an error":text)}
        var answer=root["structured_output"] as? [String:Any]
        if answer == nil,let start=text.firstIndex(of:"{"),let end=text.lastIndex(of:"}"),start<end {
            answer=try? JSONSerialization.jsonObject(with:Data(text[start...end].utf8)) as? [String:Any]
        }
        guard let answer,let verdict=answer["verdict"] as? String else {throw CropError.message("Claude did not return a verdict: "+String(text.prefix(300)))}
        let comment=(answer["comment"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        var quad:Quad?
        if let corners=answer["corners"] as? [String:Any] {
            let points=cornerKeys.compactMap{key->Point? in
                guard let corner=corners[key] as? [String:Any],let x=(corner["x"] as? NSNumber)?.doubleValue,let y=(corner["y"] as? NSNumber)?.doubleValue else {return nil}
                return Point(min(1,max(0,x)),min(1,max(0,y)))
            }
            if points.count == 4 {let proposed=Quad(points);if proposed.valid,proposed.distance(current)>0.002 {quad=proposed}}
        }
        let good=verdict == "good"
        var moved:PageSplit?
        if let split,let line=answer["split"] as? [String:Any] {
            let ends=splitKeys.compactMap{key->(u:Double,v:Double)? in
                guard let end=line[key] as? [String:Any],let x=(end["x"] as? NSNumber)?.doubleValue,let y=(end["y"] as? NSNumber)?.doubleValue else {return nil}
                return SplitGeometry.position(of:Point(x,y),quad:current,rotation:rotation)
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
    /// Writes the two reduced images Claude reads. The original photograph is not altered or sent at full size.
    public static func prepare(_ page: Page, in directory: URL) throws {
        let photo=try Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1568)
        try Exporter.encode(photo,as:.jpeg,quality:0.82,dpi:nil).write(to:directory.appendingPathComponent(photoName))
        try Exporter.encode(overlay(photo,quad:page.quad,split:splitEnds(page)),as:.jpeg,quality:0.82,dpi:nil).write(to:directory.appendingPathComponent(overlayName))
    }
    /// The tool is often a script whose interpreter sits beside it or in a package manager's folder, and an app
    /// opened from Finder has only the system's bare search path.
    public static func environment(base: [String:String], apiKey: String, executable: URL, home: String) -> [String:String] {
        var environment=base,path:[String]=[]
        let folders=[executable.deletingLastPathComponent().path,home+"/.local/bin","/opt/homebrew/bin","/usr/local/bin"]+(base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator:":").map(String.init)
        for folder in folders where !folder.isEmpty && !path.contains(folder) {path.append(folder)}
        environment["PATH"]=path.joined(separator:":");environment["ANTHROPIC_API_KEY"]=apiKey
        return environment
    }
    public static func failureMessage(timedOut: Bool, timeout: TimeInterval, stopped: Bool, status: Int32, detail: String) -> String {
        let minutes=max(1,Int((timeout/60).rounded()))
        if timedOut {return "Claude did not answer within \(minutes) minute\(minutes == 1 ? "":"s")"}
        if stopped {return "Claude was stopped before it answered"}
        let trimmed=detail.trimmingCharacters(in:.whitespacesAndNewlines)
        return trimmed.isEmpty ? "Claude exited with status \(status) and no reply":trimmed
    }
    private static var located: URL?
    /// Looked up once; the fallback asks a login shell and is too slow to repeat.
    public static func locateExecutable() -> URL? {
        if let located,FileManager.default.isExecutableFile(atPath:located.path) {return located}
        located=findExecutable();return located
    }
    static func findExecutable() -> URL? {
        let home=FileManager.default.homeDirectoryForCurrentUser.path
        let candidates=[home+"/.local/bin/claude",home+"/.claude/local/claude","/opt/homebrew/bin/claude","/usr/local/bin/claude"]
        if let found=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) {return URL(fileURLWithPath:found)}
        // Apps launched from Finder do not inherit the shell's PATH.
        let shell=Process(),pipe=Pipe()
        shell.executableURL=URL(fileURLWithPath:"/bin/zsh");shell.arguments=["-lc","command -v claude"];shell.standardOutput=pipe;shell.standardError=FileHandle.nullDevice
        guard (try? shell.run()) != nil else {return nil}
        let path=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        shell.waitUntilExit()
        return FileManager.default.isExecutableFile(atPath:path) ? URL(fileURLWithPath:path):nil
    }
    /// Blocks until Claude answers. `started` receives the process so the caller can cancel it.
    public static func run(_ page: Page, model: String, apiKey: String, executable: URL, timeout: TimeInterval = 240, started: (Process) -> Void = {_ in}) throws -> CropReview {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("KettleStitch-review-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        try prepare(page,in:directory)
        let process=Process(),output=Pipe(),errors=Pipe()
        process.executableURL=executable;let ends=splitEnds(page);process.arguments=arguments(model:model,prompt:prompt(quad:page.quad,split:ends),split:ends != nil);process.currentDirectoryURL=directory
        process.environment=environment(base:ProcessInfo.processInfo.environment,apiKey:apiKey,executable:executable,home:FileManager.default.homeDirectoryForCurrentUser.path)
        process.standardInput=FileHandle.nullDevice;process.standardOutput=output;process.standardError=errors
        try process.run();started(process)
        let timedOut=TimedOut()
        let deadline=DispatchWorkItem{if process.isRunning {timedOut.value=true;process.terminate()}}
        DispatchQueue.global().asyncAfter(deadline:.now()+timeout,execute:deadline)
        var errorData=Data();let group=DispatchGroup()
        DispatchQueue.global().async(group:group){errorData=errors.fileHandleForReading.readDataToEndOfFile()}
        let data=output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit();group.wait();deadline.cancel()
        let stopped=process.terminationReason == .uncaughtSignal
        if stopped || data.isEmpty {
            throw CropError.message(failureMessage(timedOut:timedOut.value,timeout:timeout,stopped:stopped,status:process.terminationStatus,detail:String(decoding:errorData.suffix(400),as:UTF8.self)))
        }
        return try parse(data,current:page.quad,split:ends == nil ? nil:page.split,rotation:page.rotation)
    }
}

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Vision

public struct ExportOptions: Codable, Equatable {
    public enum Format: String, Codable, CaseIterable {
        case pdf, jpeg, png, tiff
        public var title: String {rawValue.uppercased()}
        public var fileExtension: String {self == .jpeg ? "jpg":rawValue}
        public var type: UTType {
            switch self {case .pdf:return .pdf;case .jpeg:return .jpeg;case .png:return .png;case .tiff:return .tiff}
        }
    }
    public var format = Format.pdf
    public var searchableText = false
    /// Vision language identifier; nil detects the language automatically.
    public var textLanguage: String?
    /// Replaces each page's own cleanup mode when set.
    public var cleanupOverride: Cleanup?
    public var jpegQuality = 0.85
    public var maxDPI: Double?
    /// How split spreads are written; nil means left page first.
    public var splitOrder: SplitOrder?
    public var password: String?
    public init() {}
    /// Why Core Graphics cannot protect a PDF with this password, or nil if it can.
    public static func passwordProblem(_ password: String) -> String? {
        if password.isEmpty {return "Enter a password."}
        if !password.unicodeScalars.allSatisfy({$0.isASCII && $0.value>=32 && $0.value<127}) {return "Use only unaccented letters, digits and common symbols; PDF protection cannot store other characters."}
        if password.utf8.count>32 {return "Use at most 32 characters; anything longer would be cut off."}
        return nil
    }
    // The password is never persisted with the other choices.
    private enum CodingKeys: String, CodingKey {case format, searchableText, textLanguage, cleanupOverride, jpegQuality, maxDPI, splitOrder}
}
public enum SplitOrder: String, Codable, CaseIterable {
    case leftFirst, rightFirst, ignore
    public var title: String {
        switch self {case .leftFirst:return "Left Page First";case .rightFirst:return "Right Page First";case .ignore:return "Ignore Splits"}
    }
}
public struct RenderedPage {
    public let image: CGImage
    public let layout: OutputLayout
}
/// A recognized line; the box is normalized with a bottom-left origin.
public struct TextLine {
    public let string: String
    public let box: CGRect
}
public enum Exporter {
    public static func adjustments(for page: Page, options: ExportOptions) -> Adjustments {
        var result=page.adjustments ?? Adjustments()
        if let override=options.cleanupOverride {result.cleanup=override}
        return result
    }
    /// The crops a page is exported as: the whole crop, or its two pages in reading order.
    public static func quads(for page: Page, options: ExportOptions) -> [Quad] {
        guard options.splitOrder != .ignore,let split=page.split,let parts=SplitGeometry.parts(split,quad:page.quad,rotation:page.rotation) else {return [page.quad]}
        return options.splitOrder == .rightFirst ? Array(parts.reversed()):parts
    }
    /// The whole crop, ignoring any split.
    public static func render(_ page: Page, options: ExportOptions) throws -> RenderedPage {
        var whole=options;whole.splitOrder = .ignore
        return try renderAll(page,options:whole)[0]
    }
    /// Decodes one full-resolution source, so callers should render pages one at a time.
    public static func renderAll(_ page: Page, options: ExportOptions) throws -> [RenderedPage] {
        let source=try Imaging.load(URL(fileURLWithPath:page.path),maxPixel:100000)
        let estimate=OutputGeometry.pixelSize(quad:page.quad,sourceWidth:Double(source.width),sourceHeight:Double(source.height),rotation:page.rotation)
        let native=OutputGeometry.layout(pixelWidth:Double(estimate.width),pixelHeight:Double(estimate.height),format:page.format)
        let settings=adjustments(for:page,options:options)
        let crops=quads(for:page,options:options)
        let fitted=page.format?.fitInto != nil
        let zones=(page.pictureZones ?? []).compactMap{$0.outline(quad:page.quad,rotation:page.rotation)}
        return try crops.enumerated().map{position,quad in
            // Deskew angles are stored left page first, whichever page is written first.
            let part=options.splitOrder == .rightFirst ? crops.count-1-position:position
            // A half fitted to its own sheet has its own resolution; otherwise halves share the spread's.
            var partDPI=native.dpi
            if crops.count>1,fitted {
                let size=OutputGeometry.pixelSize(quad:quad,sourceWidth:Double(source.width),sourceHeight:Double(source.height),rotation:page.rotation)
                partDPI=OutputGeometry.layout(pixelWidth:Double(size.width),pixelHeight:Double(size.height),format:page.format).dpi
            }
            let scale=options.maxDPI.map{min(1,$0/partDPI)} ?? 1
            var image=try Imaging.corrected(source,quad:quad,rotation:page.rotation,adjustments:settings,scale:scale,deskew:page.deskewAngle(part:part,of:crops.count),zones:zones)
            // A page with a picture on it needs its gray levels; pure text packs into one bit.
            if settings.cleanup == .blackAndWhite,options.format != .jpeg,!Imaging.hasPictures(zones,quad:quad,rotation:page.rotation) {image=try Imaging.bilevel(image)}
            let width=Double(image.width)/scale,height=Double(image.height)/scale
            var layout:OutputLayout
            if crops.count == 1 || fitted {layout=OutputGeometry.layout(pixelWidth:width,pixelHeight:height,format:page.format)}
            else {
                // Each half keeps the spread's resolution instead of being stretched to the spread's width.
                let size=CGSize(width:width/native.dpi*72,height:height/native.dpi*72)
                layout=OutputLayout(pageSize:size,imageRect:CGRect(origin:.zero,size:size),dpi:native.dpi)
            }
            layout.dpi*=scale
            return RenderedPage(image:image,layout:layout)
        }
    }
    /// The black band between the two pages of a split spread in the preview: a fiftieth of their width,
    /// so it shows as clearly in a sidebar picture as on the canvas.
    public static let previewGapGray = 0.0
    public static func previewGap(between widths: [Int]) -> Int {max(2,widths.reduce(0,+)/50)}
    /// How many pages the preview of `page` shows.
    public static func previewParts(_ page: Page) -> Int {quads(for:page,options:ExportOptions()).count}
    /// What export will produce from an already decoded photograph: the corrected crop, or for a split spread
    /// its two pages side by side, each with its own deskew, cleanup and picture zones.
    public static func preview(_ source: CGImage, page: Page) throws -> CGImage {
        let crops=quads(for:page,options:ExportOptions())
        let zones=(page.pictureZones ?? []).compactMap{$0.outline(quad:page.quad,rotation:page.rotation)}
        let settings=page.adjustments ?? Adjustments()
        let parts=try crops.enumerated().map{part,quad in
            try Imaging.corrected(source,quad:quad,rotation:page.rotation,adjustments:settings,deskew:page.deskewAngle(part:part,of:crops.count),zones:zones)
        }
        guard parts.count>1 else {return parts[0]}
        let gap=previewGap(between:parts.map{$0.width})
        let width=parts.reduce(0){$0+$1.width}+gap*(parts.count-1),height=parts.map{$0.height}.max()!
        guard let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw CropError.message("Could not render preview")}
        c.setFillColor(CGColor(gray:previewGapGray,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height))
        var x=0
        for part in parts {c.draw(part,in:CGRect(x:x,y:height-part.height,width:part.width,height:part.height));x+=part.width+gap}
        guard let result=c.makeImage() else {throw CropError.message("Could not render preview")}
        return result
    }
    public static func encode(_ image: CGImage, as type: UTType, quality: Double, dpi: Double?) throws -> Data {
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data,type.identifier as CFString,1,nil) else {throw CropError.message("Cannot create export")}
        var properties:[CFString:Any]=[kCGImageDestinationLossyCompressionQuality:quality]
        if let dpi {properties[kCGImagePropertyDPIWidth]=dpi;properties[kCGImagePropertyDPIHeight]=dpi}
        if type == .tiff {properties[kCGImagePropertyTIFFDictionary]=[kCGImagePropertyTIFFCompression:5]}
        CGImageDestinationAddImage(destination,image,properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {throw CropError.message("Export failed")}
        return data as Data
    }
    public static func writeImage(_ page: Page, to url: URL, options: ExportOptions) throws {
        let rendered=try render(page,options:options)
        try encode(rendered.image,as:options.format.type,quality:options.jpegQuality,dpi:rendered.layout.dpi).write(to:url)
    }
    /// Writes `name.ext`, or `name-1.ext` and `name-2.ext` for a split spread. Each file appears only when complete.
    @discardableResult public static func writeImages(_ page: Page, in directory: URL, name: String, options: ExportOptions) throws -> [URL] {
        let rendered=try renderAll(page,options:options)
        return try rendered.enumerated().map{index,part in
            let url=directory.appendingPathComponent(name+(rendered.count>1 ? "-\(index+1)":"")+"."+options.format.fileExtension)
            try encode(part.image,as:options.format.type,quality:options.jpegQuality,dpi:part.layout.dpi).write(to:url,options:.atomic)
            return url
        }
    }
    public static var textLanguages: [String] {
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }
    public static func recognizeText(in image: CGImage, language: String?) throws -> [TextLine] {
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=true
        if let language {request.recognitionLanguages=[language]} else {request.automaticallyDetectsLanguage=true}
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap{observation in
            observation.topCandidates(1).first.map{TextLine(string:$0.string,box:observation.boundingBox)}
        }
    }
}
/// Removes the document information (Producer, Creator, dates) from a finished PDF by blanking the dictionary
/// in place, so no offset in the file moves. It works the same on a password-protected file.
public enum PDFInfo {
    public static func strip(_ url: URL) throws {
        let failure=CropError.message("Could not remove the document information from \(url.lastPathComponent)")
        let file=try FileHandle(forUpdating:url);defer {try? file.close()}
        let size=try file.seekToEnd()
        func read(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
            try file.seek(toOffset:offset);return [UInt8](try file.read(upToCount:count) ?? Data())
        }
        func text(_ bytes: [UInt8]) -> String {String(decoding:bytes,as:UTF8.self)}
        func number(after key: String, in s: String) -> UInt64? {
            guard let found=s.range(of:key,options:.backwards) else {return nil}
            return UInt64(s[found.upperBound...].drop{$0.isWhitespace}.prefix{$0.isNumber})
        }
        let tail=text(try read(size>2048 ? size-2048:0,2048))
        // A file without an information dictionary has nothing to remove.
        guard let object=number(after:"/Info",in:tail) else {return}
        guard let table=number(after:"startxref",in:tail) else {throw failure}
        // A classic cross-reference table: a header line, then one 20-byte entry per object from zero.
        let header=try read(table,64)
        guard text(header).hasPrefix("xref"),let lines=Optional(header.split(separator:10,maxSplits:2,omittingEmptySubsequences:false)),lines.count==3,
              text(Array(lines[1])).trimmingCharacters(in:.whitespaces).hasPrefix("0 ") else {throw failure}
        let entries=table+UInt64(lines[0].count+lines[1].count+2)
        guard let offset=UInt64(text(try read(entries+object*20,10))) else {throw failure}
        let body=try read(offset,8192)
        guard text(body).hasPrefix("\(object) 0 obj"),let open=body.indices.dropLast().first(where:{body[$0]==60 && body[$0+1]==60}) else {throw failure}
        // Find the closing >> of the dictionary, stepping over strings, which may hold any bytes.
        var i=open+2,depth=0,close:Int?
        while i<body.count-1 {
            let byte=body[i]
            if depth>0 {if byte==92 {i+=1} else if byte==40 {depth+=1} else if byte==41 {depth-=1}}
            else if byte==40 {depth=1}
            else if byte==62,body[i+1]==62 {close=i;break}
            i+=1
        }
        guard let close else {throw failure}
        try file.seek(toOffset:offset+UInt64(open+2));try file.write(contentsOf:Data(repeating:32,count:close-open-2))
    }
}
/// Writes pages one at a time so a long book never holds more than one decoded photograph.
public final class PDFWriter {
    private let context: CGContext
    private var closed=false
    private let url: URL
    public init(url: URL, password: String? = nil) throws {
        self.url=url
        var info:[CFString:Any]=[:]
        if let password,!password.isEmpty {info[kCGPDFContextUserPassword]=password;info[kCGPDFContextOwnerPassword]=password}
        guard let context=CGContext(url as CFURL,mediaBox:nil,info as CFDictionary) else {throw CropError.message("Cannot create PDF: \(url.lastPathComponent)")}
        self.context=context
    }
    deinit {try? close()}
    /// Adds one PDF page, or two for a split spread.
    public func add(_ page: Page, options: ExportOptions) throws {for part in try Exporter.renderAll(page,options:options) {try add(part,options:options)}}
    public func add(_ rendered: RenderedPage, options: ExportOptions) throws {
        var image=rendered.image
        if image.bitsPerComponent != 1 {
            // A JPEG-backed image is embedded as it stands instead of being recompressed losslessly.
            let data=try Exporter.encode(image,as:.jpeg,quality:options.jpegQuality,dpi:nil)
            guard let provider=CGDataProvider(data:data as CFData),let jpeg=CGImage(jpegDataProviderSource:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw CropError.message("Could not compress page")}
            image=jpeg
        }
        let lines=options.searchableText ? try Exporter.recognizeText(in:rendered.image,language:options.textLanguage):[]
        var box=CGRect(origin:.zero,size:rendered.layout.pageSize)
        let media=Data(bytes:&box,count:MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox:media] as CFDictionary)
        context.draw(image,in:rendered.layout.imageRect)
        draw(lines,in:rendered.layout.imageRect)
        context.endPDFPage()
    }
    /// Finishes the file, then empties its information dictionary: Quartz always writes the macOS version and
    /// build as Producer, and the creation and modification dates.
    public func close() throws {if !closed {closed=true;context.closePDF();try PDFInfo.strip(url)}}
    /// Invisible text placed over each recognized line so the PDF can be searched and copied.
    private func draw(_ lines: [TextLine], in rect: CGRect) {
        for line in lines {
            let box=CGRect(x:rect.minX+line.box.minX*rect.width,y:rect.minY+line.box.minY*rect.height,width:line.box.width*rect.width,height:line.box.height*rect.height)
            guard box.width>0.5,box.height>0.5 else {continue}
            if box.height>box.width*1.5,line.string.count>1 {
                // A vertical line is one run turned to read downward, so its words stay searchable.
                context.saveGState()
                context.translateBy(x:box.minX,y:box.maxY);context.rotate(by:-.pi/2)
                draw(line.string,in:CGRect(x:0,y:0,width:box.height,height:box.width))
                context.restoreGState()
            } else {draw(line.string,in:box)}
        }
    }
    private func draw(_ string: String, in box: CGRect) {
        let font=CTFontCreateWithName("Helvetica" as CFString,max(1,box.height*0.8),nil)
        let clear=CGColor(gray:0,alpha:0)
        let attributed=NSAttributedString(string:string,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):clear])
        let line=CTLineCreateWithAttributedString(attributed)
        let width=CTLineGetTypographicBounds(line,nil,nil,nil)
        guard width>0 else {return}
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.translateBy(x:box.minX,y:box.minY+box.height*0.2)
        context.scaleBy(x:box.width/CGFloat(width),y:1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line,context)
        context.restoreGState()
    }
}

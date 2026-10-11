import XCTest
@testable import CropCore
import CoreGraphics
import CoreImage
import CoreText
import PDFKit

/// A shaded sheet with dark print, standing in for an unevenly lit page.
private func shadedPage(width:Int=800,height:Int=600,text:String?=nil)->CGImage {
    let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors=[CGColor(red:0.55,green:0.52,blue:0.45,alpha:1),CGColor(red:0.9,green:0.87,blue:0.8,alpha:1)] as CFArray
    c.drawLinearGradient(CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!,start:.zero,end:CGPoint(x:width,y:0),options:[])
    c.setFillColor(CGColor(gray:0.1,alpha:1))
    if let text {
        let font=CTFontCreateWithName("Helvetica-Bold" as CFString,CGFloat(height)/8,nil)
        let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font]))
        c.textPosition=CGPoint(x:CGFloat(width)*0.08,y:CGFloat(height)*0.45);CTLineDraw(line,c)
    } else {
        for x in stride(from:100,to:width-100,by:12) {c.fill(CGRect(x:x,y:height/2-40,width:3,height:80))}
    }
    return c.makeImage()!
}
private func gray(_ image:CGImage,_ x:Int,_ y:Int)->Double {
    var pixel=[UInt8](repeating:0,count:4)
    let c=CGContext(data:&pixel,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .none
    c.draw(image,in:CGRect(x:-CGFloat(x),y:-CGFloat(image.height-1-y),width:CGFloat(image.width),height:CGFloat(image.height)))
    return (Double(pixel[0])+Double(pixel[1])+Double(pixel[2]))/765
}
private func temporaryPhoto(_ image:CGImage)throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
    try Exporter.encode(image,as:.jpeg,quality:0.95,dpi:nil).write(to:url)
    return url
}

final class SettingsModelTests:XCTestCase {
    func testOlderProjectsStillDecode() throws {
        let json=#"{"version":1,"selected":0,"pages":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","path":"/photos/a.jpg","quad":{"points":[{"x":0,"y":0},{"x":1,"y":0},{"x":1,"y":1},{"x":0,"y":1}]},"candidates":[],"status":"Pending","reviewed":false,"rotation":0,"revision":0}]}"#
        let project=try JSONDecoder().decode(Project.self,from:Data(json.utf8))
        XCTAssertNil(project.pages[0].adjustments);XCTAssertNil(project.pages[0].format);XCTAssertNil(project.pages[0].flagged)
    }
    func testSettingsRoundTrip() throws {
        var page=Page(path:"/photos/a.jpg")
        var a=Adjustments();a.cleanup = .blackAndWhite;a.brightness=0.25;a.contrast = -0.5
        page.adjustments=a;page.format=PageFormat(widthCM:28,fitInto:.a4);page.flagged=true;page.reviewNote="Top-left moved"
        let copy=try JSONDecoder().decode(Page.self,from:JSONEncoder().encode(page))
        XCTAssertEqual(copy.adjustments,a);XCTAssertEqual(copy.format,PageFormat(widthCM:28,fitInto:.a4));XCTAssertEqual(copy.flagged,true);XCTAssertEqual(copy.reviewNote,"Top-left moved")
        XCTAssertTrue(Adjustments().isIdentity);XCTAssertFalse(a.isIdentity)
    }
    func testExportOptionsNeverPersistPassword() throws {
        var options=ExportOptions();options.password="secret";options.maxDPI=300;options.cleanupOverride = .grayscale
        let data=try JSONEncoder().encode(options)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("secret"))
        let copy=try JSONDecoder().decode(ExportOptions.self,from:data)
        XCTAssertNil(copy.password);XCTAssertEqual(copy.maxDPI,300);XCTAssertEqual(copy.cleanupOverride,.grayscale)
    }
}

final class OutputGeometryTests:XCTestCase {
    func testPixelSizeFollowsCropAndRotation() {
        let q=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
        let upright=OutputGeometry.pixelSize(quad:q,sourceWidth:4000,sourceHeight:3000,rotation:0)
        XCTAssertEqual(upright.width,3200,accuracy:0.001);XCTAssertEqual(upright.height,2400,accuracy:0.001)
        let turned=OutputGeometry.pixelSize(quad:q,sourceWidth:4000,sourceHeight:3000,rotation:3)
        XCTAssertEqual(turned.width,2400,accuracy:0.001);XCTAssertEqual(turned.height,3200,accuracy:0.001)
    }
    func testUnsizedPageAssumes300DPI() {
        let layout=OutputGeometry.layout(pixelWidth:3000,pixelHeight:1500,format:nil)
        XCTAssertEqual(layout.dpi,300);XCTAssertEqual(layout.pageSize.width,720,accuracy:0.001);XCTAssertEqual(layout.pageSize.height,360,accuracy:0.001)
        XCTAssertEqual(layout.imageRect,CGRect(origin:.zero,size:layout.pageSize))
    }
    func testPhysicalWidthSetsResolution() {
        let layout=OutputGeometry.layout(pixelWidth:5080,pixelHeight:2540,format:PageFormat(widthCM:25.4))
        XCTAssertEqual(layout.dpi,508,accuracy:0.001);XCTAssertEqual(layout.pageSize.width,720,accuracy:0.001);XCTAssertEqual(layout.pageSize.height,360,accuracy:0.001)
    }
    func testFitIntoPaperTurnsAndCentres() {
        let layout=OutputGeometry.layout(pixelWidth:4000,pixelHeight:2000,format:PageFormat(widthCM:99,fitInto:.a4))
        XCTAssertEqual(layout.pageSize.width,29.7/2.54*72,accuracy:0.001);XCTAssertEqual(layout.pageSize.height,21.0/2.54*72,accuracy:0.001)
        XCTAssertEqual(layout.imageRect.width,layout.pageSize.width,accuracy:0.001);XCTAssertEqual(layout.imageRect.midY,layout.pageSize.height/2,accuracy:0.001)
        XCTAssertEqual(layout.dpi,4000/(29.7/2.54),accuracy:0.01)
        let portrait=OutputGeometry.layout(pixelWidth:1000,pixelHeight:3000,format:PageFormat(fitInto:.a4))
        XCTAssertLessThan(portrait.pageSize.width,portrait.pageSize.height);XCTAssertEqual(portrait.imageRect.height,portrait.pageSize.height,accuracy:0.001)
    }
}

final class CleanupTests:XCTestCase {
    func testCleanupEvensShadingAndKeepsPrint() throws {
        let image=shadedPage()
        var a=Adjustments();a.cleanup = .color
        let cleaned=try Imaging.corrected(image,quad:.full,adjustments:a)
        XCTAssertGreaterThan(gray(cleaned,40,60),0.9);XCTAssertGreaterThan(gray(cleaned,760,60),0.9)
        XCTAssertLessThan(abs(gray(cleaned,40,60)-gray(cleaned,760,60)),0.05,"Shading should be evened out")
        XCTAssertLessThan(gray(cleaned,101,300),0.45,"Print must stay dark")
        XCTAssertEqual(cleaned.bitsPerPixel,32)
    }
    func testBrightnessAndContrast() throws {
        let image=shadedPage()
        var brighter=Adjustments();brighter.brightness=0.5
        XCTAssertGreaterThan(gray(try Imaging.corrected(image,quad:.full,adjustments:brighter),400,60),gray(image,400,60)+0.05)
        var punchy=Adjustments();punchy.contrast=1
        let result=try Imaging.corrected(image,quad:.full,adjustments:punchy)
        XCTAssertGreaterThan(gray(result,780,60)-gray(result,101,300),gray(image,780,60)-gray(image,101,300))
    }
    func testGrayscaleAndBlackAndWhite() throws {
        let image=shadedPage()
        var a=Adjustments();a.cleanup = .grayscale
        XCTAssertEqual(try Imaging.corrected(image,quad:.full,adjustments:a).bitsPerPixel,8)
        a.cleanup = .blackAndWhite
        let mono=try Imaging.corrected(image,quad:.full,adjustments:a)
        for (x,y) in [(40,60),(760,60),(400,500)] {XCTAssertGreaterThan(gray(mono,x,y),0.98)}
        XCTAssertLessThan(gray(mono,101,300),0.02)
        let packed=try Imaging.bilevel(mono)
        XCTAssertEqual(packed.bitsPerPixel,1);XCTAssertEqual(packed.width,mono.width)
        XCTAssertGreaterThan(gray(packed,40,60),0.98);XCTAssertLessThan(gray(packed,101,300),0.02)
    }
    func testScaleReducesPixels() throws {
        let half=try Imaging.corrected(shadedPage(),quad:.full,scale:0.5)
        XCTAssertEqual(half.width,400,accuracy:2);XCTAssertEqual(half.height,300,accuracy:2)
    }
}

final class ExportTests:XCTestCase {
    func testPDFPagesSizesAndPassword() throws {
        let photo=try temporaryPhoto(shadedPage(width:1200,height:900))
        let pdf=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
        defer{try? FileManager.default.removeItem(at:photo);try? FileManager.default.removeItem(at:pdf)}
        var first=Page(path:photo.path);first.format=PageFormat(fitInto:.a4)
        var second=Page(path:photo.path);second.rotation=1
        var bw=Adjustments();bw.cleanup = .blackAndWhite;second.adjustments=bw
        var options=ExportOptions();options.password="open sesame"
        let writer=try PDFWriter(url:pdf,password:options.password)
        try writer.add(first,options:options);try writer.add(second,options:options);try writer.close()
        let document=try XCTUnwrap(PDFDocument(url:pdf))
        XCTAssertTrue(document.isEncrypted);XCTAssertTrue(document.isLocked)
        XCTAssertTrue(document.unlock(withPassword:"open sesame"))
        XCTAssertTrue((document.documentAttributes ?? [:]).isEmpty,"No producer, creator or dates in a protected file: \(document.documentAttributes ?? [:])")
        XCTAssertEqual(document.pageCount,2)
        let a4=try XCTUnwrap(document.page(at:0)).bounds(for:.mediaBox)
        XCTAssertEqual(a4.width,29.7/2.54*72,accuracy:0.5);XCTAssertEqual(a4.height,21.0/2.54*72,accuracy:0.5)
        let turned=try XCTUnwrap(document.page(at:1)).bounds(for:.mediaBox)
        XCTAssertEqual(turned.width,900.0/300*72,accuracy:1);XCTAssertEqual(turned.height,1200.0/300*72,accuracy:1)
    }
    func testMaximumDPIAndQualityShrinkOutput() throws {
        let photo=try temporaryPhoto(shadedPage(width:1200,height:900))
        defer{try? FileManager.default.removeItem(at:photo)}
        let page=Page(path:photo.path)
        var options=ExportOptions();options.format = .jpeg
        let full=try Exporter.render(page,options:options)
        XCTAssertEqual(full.image.width,1200,accuracy:2);XCTAssertEqual(full.layout.dpi,300,accuracy:0.001)
        options.maxDPI=150
        let limited=try Exporter.render(page,options:options)
        XCTAssertEqual(limited.image.width,600,accuracy:2);XCTAssertEqual(limited.layout.dpi,150,accuracy:0.001)
        XCTAssertEqual(limited.layout.pageSize.width,full.layout.pageSize.width,accuracy:1,"The physical page must not shrink")
        options.maxDPI=600
        XCTAssertEqual(try Exporter.render(page,options:options).image.width,1200,accuracy:2,"Never upsample")
        let fine=try Exporter.encode(full.image,as:.jpeg,quality:0.95,dpi:300),coarse=try Exporter.encode(full.image,as:.jpeg,quality:0.3,dpi:300)
        XCTAssertLessThan(coarse.count,fine.count)
    }
    func testCleanupOverrideAndBilevelFormats() throws {
        let photo=try temporaryPhoto(shadedPage())
        defer{try? FileManager.default.removeItem(at:photo)}
        let page=Page(path:photo.path)
        var options=ExportOptions();options.format = .png;options.cleanupOverride = .blackAndWhite
        XCTAssertEqual(try Exporter.render(page,options:options).image.bitsPerPixel,1)
        options.format = .jpeg
        XCTAssertEqual(try Exporter.render(page,options:options).image.bitsPerPixel,8)
        let out=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".tiff")
        defer{try? FileManager.default.removeItem(at:out)}
        options.format = .tiff
        try Exporter.writeImage(page,to:out,options:options)
        XCTAssertEqual(try Imaging.load(out,maxPixel:4000).width,800,accuracy:2)
    }
    func testSearchablePDFContainsRecognizedText() throws {
        let photo=try temporaryPhoto(shadedPage(width:1600,height:800,text:"HELLO WORLD 1940"))
        let pdf=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
        defer{try? FileManager.default.removeItem(at:photo);try? FileManager.default.removeItem(at:pdf)}
        var options=ExportOptions();options.searchableText=true;options.textLanguage="en-US"
        let writer=try PDFWriter(url:pdf)
        try writer.add(Page(path:photo.path),options:options);try writer.close()
        let text=try XCTUnwrap(PDFDocument(url:pdf)?.string)
        XCTAssertTrue(text.contains("HELLO"),"Found: \(text)");XCTAssertTrue(text.contains("1940"),"Found: \(text)")
        options.searchableText=false
        let plain=try PDFWriter(url:pdf);try plain.add(Page(path:photo.path),options:options);try plain.close()
        XCTAssertEqual((PDFDocument(url:pdf)?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines),"")
        // Quartz writes the macOS version and build, and the time of export; none of it is left in the file.
        let bytes=String(decoding:try Data(contentsOf:pdf),as:UTF8.self)
        for word in ["Producer","Creator","CreationDate","ModDate","Quartz","macOS"] {XCTAssertFalse(bytes.contains(word),word)}
        XCTAssertTrue((PDFDocument(url:pdf)?.documentAttributes ?? [:]).isEmpty)
    }
}

/// Answers requests from a script instead of the network, and keeps what was asked.
final class ScriptedProtocol: URLProtocol {
    static var replies:[(status:Int,headers:[String:String],body:Data)]=[]
    static var requests:[URLRequest]=[]
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading(){
        ScriptedProtocol.requests.append(request)
        let reply=ScriptedProtocol.replies.isEmpty ? (status:500,headers:[:],body:Data()):ScriptedProtocol.replies.removeFirst()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:"HTTP/1.1",headerFields:reply.headers)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:reply.body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}
final class ClaudeReviewTests:XCTestCase {
    func testARequestIsRetriedWhenTheServiceIsBusyAndItsAnswerBecomesAReview() throws {
        let photo=try temporaryPhoto(shadedPage(width:1200,height:800));defer{try? FileManager.default.removeItem(at:photo)}
        var page=Page(path:photo.path);page.quad=current
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[ScriptedProtocol.self]
        let session=URLSession(configuration:configuration)
        let body=#"{"verdict":"adjust","comment":"TL moved out","corners":{"top_left":{"x":0.05,"y":0.06},"top_right":{"x":0.9,"y":0.1},"bottom_right":{"x":0.9,"y":0.9},"bottom_left":{"x":0.1,"y":0.9}}}"#
        let good=try JSONSerialization.data(withJSONObject:["type":"message","stop_reason":"end_turn","content":[["type":"text","text":body]],"usage":["input_tokens":2000,"output_tokens":100]] as [String:Any])
        ScriptedProtocol.requests=[];ScriptedProtocol.replies=[(429,["retry-after":"0"],Data(#"{"type":"error","error":{"message":"busy"}}"#.utf8)),(200,[:],good)]
        var started=0
        let review=try ClaudeReview.run(page,model:ReviewModel.chosen("claude-sonnet-5-5",for:.anthropic),apiKey:"sk-test",session:session){_ in started+=1}
        XCTAssertEqual(started,2,"Busy the first time, so it was asked again");XCTAssertEqual(ScriptedProtocol.requests.count,2)
        XCTAssertEqual(ScriptedProtocol.requests.last?.url?.absoluteString,"https://api.anthropic.com/v1/messages")
        XCTAssertEqual(review.quad?.points[0],Point(0.05,0.06));XCTAssertEqual(review.comment,"TL moved out")
        // 2,000 tokens in and 100 out on Sonnet 5.5, at $2 and $10 a million.
        XCTAssertEqual(review.usage?.inputTokens,2000);XCTAssertEqual(try XCTUnwrap(review.usage?.cost),0.005,accuracy:1e-12)
        // A rejected key is not retried.
        ScriptedProtocol.requests=[];ScriptedProtocol.replies=[(401,[:],Data(#"{"type":"error","error":{"message":"invalid x-api-key"}}"#.utf8))]
        XCTAssertThrowsError(try ClaudeReview.run(page,model:ReviewModel.chosen(nil,for:.anthropic),apiKey:"sk-bad",session:session)){XCTAssertTrue($0.localizedDescription.hasPrefix("Claude rejected the API key."))}
        XCTAssertEqual(ScriptedProtocol.requests.count,1)
    }
    func testTokenUseIsReadAddedUpAndLogged() throws {
        let body=#"{"verdict":"good","comment":"ok","corners":{"top_left":{"x":0.1,"y":0.1},"top_right":{"x":0.9,"y":0.1},"bottom_right":{"x":0.9,"y":0.9},"bottom_left":{"x":0.1,"y":0.9}}}"#
        let reply=try JSONSerialization.data(withJSONObject:["type":"message","stop_reason":"end_turn","content":[["type":"thinking","thinking":""],["type":"text","text":body]],"usage":["input_tokens":1200,"cache_creation_input_tokens":300,"cache_read_input_tokens":40,"output_tokens":85]] as [String:Any])
        let answer=try ReviewAPI.answer(reply,status:200,provider:.anthropic)
        XCTAssertEqual(answer.text,body);XCTAssertTrue(try ClaudeReview.parse(answer.text,current:current).good)
        var usage=try XCTUnwrap(answer.usage);XCTAssertEqual(usage,ReviewUsage(inputTokens:1540,outputTokens:85),"Cached tokens count as read")
        // Cost is worked out from list prices: 1,540 in and 85 out on Opus 5.5 at $4 and $20 a million.
        let opus=ReviewModel.chosen("claude-opus-5-5",for:.anthropic)
        XCTAssertEqual(try XCTUnwrap(opus.cost(usage)),(1540*4+85*20)/1_000_000,accuracy:1e-12)
        XCTAssertNil(ReviewModel.chosen(nil,for:.gemini).cost(usage),"No price is assumed where none is known")
        usage.cost=0.0123;XCTAssertEqual(usage.summary,"1,540 tokens in, 85 out, $0.0123")
        XCTAssertEqual((usage+ReviewUsage(inputTokens:10,outputTokens:5)).summary,"1,550 tokens in, 90 out, $0.0123")
        XCTAssertEqual(ReviewUsage(inputTokens:10,outputTokens:5).summary,"10 tokens in, 5 out")
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json");defer{try? FileManager.default.removeItem(at:url)}
        XCTAssertEqual(UsageLog.text(UsageLog.read(url)),"No requests have been sent yet.")
        try UsageLog.append(UsageEntry(date:Date(timeIntervalSince1970:1_800_000_000),file:"IMG_1.HEIC",model:"Haiku 5.5",seconds:8.4,usage:usage),to:url)
        try UsageLog.append(UsageEntry(date:Date(timeIntervalSince1970:1_800_000_060),file:"IMG_2.HEIC",model:"Haiku 5.5",seconds:11,usage:ReviewUsage(inputTokens:10,outputTokens:5)),to:url)
        let lines=UsageLog.text(UsageLog.read(url),timeZone:TimeZone(identifier:"UTC")!).components(separatedBy:"\n")
        XCTAssertEqual(lines[0],"2 requests in all: 1,550 tokens in, 90 out, $0.0123")
        XCTAssertEqual(lines[2],"2027-01-15 08:01:00  Haiku 5.5  IMG_2.HEIC  11 s  10 tokens in, 5 out","Newest first")
        XCTAssertEqual(lines[3],"2027-01-15 08:00:00  Haiku 5.5  IMG_1.HEIC  8 s  1,540 tokens in, 85 out, $0.0123")
    }
    func testAVisibleSplitIsSentAndAMovedOneComesBack() throws {
        var page=Page(path:"/photos/a.jpg");page.quad=current;page.split=PageSplit(top:0.47,bottom:0.47)
        let ends=try XCTUnwrap(ClaudeReview.splitEnds(page))
        // 47% across a crop from 0.1 to 0.9 is x 0.476 on the photograph, from its top edge to its bottom edge.
        XCTAssertEqual(ends.0.x,0.476,accuracy:1e-9);XCTAssertEqual(ends.0.y,0.1,accuracy:1e-9);XCTAssertEqual(ends.1.y,0.9,accuracy:1e-9)
        let prompt=ClaudeReview.prompt(quad:current,split:ends)
        XCTAssertTrue(prompt.contains("s1 (x 0.4760, y 0.1000)"));XCTAssertTrue(prompt.contains("s2 (x 0.4760, y 0.9000)"));XCTAssertTrue(prompt.contains("S1 and S2"))
        XCTAssertFalse(ClaudeReview.prompt(quad:current).contains("s1"),"A page without a split is asked about its crop only")
        XCTAssertFalse(ClaudeReview.schema().contains("split"))
        let schema=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(ClaudeReview.schema(split:true).utf8)) as? [String:Any])
        XCTAssertEqual(schema["required"] as? [String],["verdict","comment","corners","split"])
        let same=#""corners":{"top_left":{"x":0.1,"y":0.1},"top_right":{"x":0.9,"y":0.1},"bottom_right":{"x":0.9,"y":0.9},"bottom_left":{"x":0.1,"y":0.9}}"#
        // Claude puts the line on the fold at x 0.5, with ends a little inside the crop's edges.
        let moved=try ClaudeReview.parse(reply("{\"verdict\":\"good\",\"comment\":\"Crop fine; the line was on a frame border.\",\(same),\"split\":{\"s1\":{\"x\":0.5,\"y\":0.12},\"s2\":{\"x\":0.5,\"y\":0.88}}}"),current:current,split:page.split,rotation:0)
        XCTAssertTrue(moved.good);XCTAssertNil(moved.quad)
        XCTAssertEqual(try XCTUnwrap(moved.split).top,0.5,accuracy:1e-9);XCTAssertEqual(try XCTUnwrap(moved.split).bottom,0.5,accuracy:1e-9)
        let kept=try ClaudeReview.parse(reply("{\"verdict\":\"good\",\"comment\":\"\",\(same),\"split\":{\"s1\":{\"x\":0.476,\"y\":0.1},\"s2\":{\"x\":0.476,\"y\":0.9}}}"),current:current,split:page.split,rotation:0)
        XCTAssertNil(kept.split,"An unchanged line is no fix")
        XCTAssertNil(try ClaudeReview.parse(reply("{\"verdict\":\"good\",\"comment\":\"\",\(same),\"split\":{\"s1\":{\"x\":0.5,\"y\":0.12},\"s2\":{\"x\":0.5,\"y\":0.88}}}"),current:current).split,"Nothing was asked about a split")
        // The moved line is applied to the page, unless the line was changed while Claude was looking.
        var edited=page;edited.split=PageSplit(top:0.4,bottom:0.4)
        XCTAssertTrue(edited.record(moved,sentQuad:current,sentSplit:page.split));XCTAssertEqual(edited.split,PageSplit(top:0.4,bottom:0.4))
        XCTAssertTrue(page.record(moved,sentQuad:current,sentSplit:page.split))
        XCTAssertEqual(try XCTUnwrap(page.split).top,0.5,accuracy:1e-9);XCTAssertEqual(page.quad,current)
        XCTAssertEqual(page.reviewNote,"Claude: crop looks right; split line moved — Crop fine; the line was on a frame border.")
    }
    let current=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
    func reply(_ body:String)->String {body}
    func testAdjustedCornerBecomesProposal() throws {
        let body=#"{"verdict":"adjust","comment":"Top-left was inside the page.","corners":{"top_left":{"x":0.05,"y":0.06},"top_right":{"x":0.9,"y":0.1},"bottom_right":{"x":0.9,"y":0.9},"bottom_left":{"x":0.1,"y":0.9}}}"#
        let review=try ClaudeReview.parse(reply(body),current:current)
        XCTAssertFalse(review.good);XCTAssertEqual(review.comment,"Top-left was inside the page.")
        XCTAssertEqual(review.quad?.points[0],Point(0.05,0.06));XCTAssertEqual(review.quad?.points[2],current.points[2])
    }
    func testGoodUnchangedAndInvalidGiveNoProposal() throws {
        let same=#"{"top_left":{"x":0.1,"y":0.1},"top_right":{"x":0.9,"y":0.1},"bottom_right":{"x":0.9,"y":0.9},"bottom_left":{"x":0.1,"y":0.9}}"#
        let good=try ClaudeReview.parse(reply("{\"verdict\":\"good\",\"comment\":\"Fine.\",\"corners\":\(same)}"),current:current)
        XCTAssertTrue(good.good);XCTAssertNil(good.quad)
        XCTAssertNil(try ClaudeReview.parse(reply("{\"verdict\":\"adjust\",\"comment\":\"\",\"corners\":\(same)}"),current:current).quad)
        let crossed=#"{"top_left":{"x":0.9,"y":0.9},"top_right":{"x":0.1,"y":0.1},"bottom_right":{"x":0.9,"y":0.1},"bottom_left":{"x":0.1,"y":0.9}}"#
        XCTAssertNil(try ClaudeReview.parse(reply("{\"verdict\":\"adjust\",\"comment\":\"\",\"corners\":\(crossed)}"),current:current).quad)
    }
    func testOutOfRangeCoordinatesAreClampedAndTextFallbackWorks() throws {
        let text=#"Here you go: {"verdict":"adjust","comment":"Wider.","corners":{"top_left":{"x":-0.2,"y":0},"top_right":{"x":1.3,"y":0},"bottom_right":{"x":1,"y":1},"bottom_left":{"x":0,"y":1}}}"#
        XCTAssertEqual(try ClaudeReview.parse(text,current:current).quad,Quad.full)
        XCTAssertThrowsError(try ClaudeReview.parse("not json",current:current))
    }
    func testEachProviderGetsItsOwnRequestAndTheKeyGoesOnlyInAHeader() throws {
        let prompt=ClaudeReview.prompt(quad:current)
        XCTAssertTrue(prompt.contains("top_left (x 0.1000, y 0.1000)"));XCTAssertTrue(prompt.contains("Two images are attached"))
        XCTAssertEqual(ReviewModel.models(for:.anthropic).map{$0.id},["claude-haiku-5-5","claude-sonnet-5-5","claude-opus-5-5"])
        XCTAssertEqual(ReviewModel.models(for:.openai).map{$0.id},["gpt-6-luna","gpt-6.1-sol","gpt-6-astra"])
        XCTAssertEqual(ReviewModel.models(for:.gemini).map{$0.id},["gemini-3.5-flash-lite","gemini-3.8-flash","gemini-3.1-pro-preview"])
        XCTAssertEqual(ReviewModel.chosen("gone",for:.openai).id,"gpt-6-luna","A choice no longer offered falls back to the provider's first")
        let photo=Data([1,2,3]),overlay=Data([4,5,6]),secret="sk-secret-key"
        let hosts:[ReviewProvider:String]=[.anthropic:"api.anthropic.com",.openai:"api.openai.com",.gemini:"generativelanguage.googleapis.com"]
        let keyHeader:[ReviewProvider:String]=[.anthropic:"x-api-key",.openai:"Authorization",.gemini:"x-goog-api-key"]
        for model in ReviewModel.all {
            let request=try ReviewAPI.request(model:model,apiKey:secret,prompt:prompt,photo:photo,overlay:overlay,split:true)
            let url=try XCTUnwrap(request.url),body=try XCTUnwrap(request.httpBody),text=String(decoding:body,as:UTF8.self)
            XCTAssertEqual(url.scheme,"https");XCTAssertEqual(url.host,hosts[model.provider],"\(model.id) is sent to its own provider and nowhere else")
            XCTAssertFalse(url.absoluteString.contains(secret),"The key is never part of the address");XCTAssertFalse(text.contains(secret),"nor of the body")
            let carrying=(request.allHTTPHeaderFields ?? [:]).filter{$0.value.contains(secret)}.map{$0.key}
            XCTAssertEqual(carrying,[keyHeader[model.provider]!],"Exactly one header carries the key")
            XCTAssertEqual(request.value(forHTTPHeaderField:"User-Agent"),ReviewAPI.userAgent);XCTAssertFalse(ReviewAPI.userAgent.contains("@"))
            XCTAssertTrue(text.contains(photo.base64EncodedString()) && text.contains(overlay.base64EncodedString()),"Both pictures are attached")
            let json=try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any])
            switch model.provider {
            case .anthropic:
                XCTAssertEqual(json["model"] as? String,model.id);XCTAssertNil(json["thinking"],"These models think by default; nothing is forced")
                let config=try XCTUnwrap(json["output_config"] as? [String:Any])
                XCTAssertEqual(config["effort"] as? String,"medium");XCTAssertEqual((config["format"] as? [String:Any])?["type"] as? String,"json_schema")
                XCTAssertEqual(json["fallbacks"] as? String,model.id == "claude-haiku-5-5" ? nil:"default")
                XCTAssertEqual(request.value(forHTTPHeaderField:"anthropic-beta"),model.id == "claude-haiku-5-5" ? nil:"server-side-fallback-2026-07-01")
                XCTAssertEqual(request.value(forHTTPHeaderField:"anthropic-version"),"2023-06-01")
            case .openai:
                XCTAssertEqual(url.path,"/v1/responses")
                let format=try XCTUnwrap((json["text"] as? [String:Any])?["format"] as? [String:Any])
                XCTAssertEqual(format["type"] as? String,"json_schema");XCTAssertEqual(format["strict"] as? Bool,true)
                XCTAssertEqual((format["schema"] as? [String:Any])?["additionalProperties"] as? Bool,false)
            case .gemini:
                XCTAssertEqual(url.path,"/v1beta/models/\(model.id):generateContent")
                let schema=try XCTUnwrap((json["generationConfig"] as? [String:Any])?["responseSchema"] as? [String:Any])
                XCTAssertEqual(schema["type"] as? String,"OBJECT");XCTAssertNil(schema["additionalProperties"])
                XCTAssertEqual(((schema["properties"] as? [String:Any])?["split"] as? [String:Any])?["type"] as? String,"OBJECT")
            }
        }
        // The answer's form is closed at every level, as strict structured output requires.
        let schema=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(ClaudeReview.schema(split:true).utf8)) as? [String:Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool,false)
        let corners=try XCTUnwrap((schema["properties"] as? [String:Any])?["corners"] as? [String:Any])
        XCTAssertEqual(corners["additionalProperties"] as? Bool,false);XCTAssertEqual((corners["required"] as? [String])?.count,4)
    }
    func testRepliesFromEachProviderAreReadAndTheirRefusalsAndErrorsReported() throws {
        func data(_ object:[String:Any])->Data {try! JSONSerialization.data(withJSONObject:object)}
        let body=#"{"verdict":"good"}"#
        let openai=try ReviewAPI.answer(data(["status":"completed","output":[["type":"reasoning"],["type":"message","content":[["type":"output_text","text":body]]]],"usage":["input_tokens":900,"output_tokens":40]]),status:200,provider:.openai)
        XCTAssertEqual(openai,ReviewAnswer(text:body,usage:ReviewUsage(inputTokens:900,outputTokens:40)))
        let gemini=try ReviewAPI.answer(data(["candidates":[["content":["parts":[["text":"thinking…","thought":true],["text":body]]],"finishReason":"STOP"]],"usageMetadata":["promptTokenCount":700,"candidatesTokenCount":30,"thoughtsTokenCount":50]]),status:200,provider:.gemini)
        XCTAssertEqual(gemini,ReviewAnswer(text:body,usage:ReviewUsage(inputTokens:700,outputTokens:80)),"Thinking is billed as output and left out of the answer")
        func message(_ reply:Data,_ status:Int,_ provider:ReviewProvider)->String {
            do {_=try ReviewAPI.answer(reply,status:status,provider:provider);return "no error"} catch {return error.localizedDescription}
        }
        XCTAssertEqual(message(data(["type":"message","stop_reason":"refusal","content":[]]),200,.anthropic),"Claude declined to look at this page.")
        XCTAssertTrue(message(data(["status":"completed","output":[["type":"message","content":[["type":"refusal","refusal":"I can't help with that."]]]]]),200,.openai).contains("I can't help with that."))
        XCTAssertEqual(message(data(["promptFeedback":["blockReason":"SAFETY"]]),200,.gemini),"Gemini declined to look at this page (SAFETY).")
        XCTAssertTrue(message(data(["status":"incomplete","incomplete_details":["reason":"max_output_tokens"]]),200,.openai).contains("max_output_tokens"))
        let rejected=message(data(["type":"error","error":["type":"authentication_error","message":"invalid x-api-key"]]),401,.anthropic)
        XCTAssertTrue(rejected.hasPrefix("Claude rejected the API key.") && rejected.contains("invalid x-api-key"))
        XCTAssertTrue(message(data(["error":["message":"API key not valid.","status":"INVALID_ARGUMENT"]]),400,.gemini).contains("API key not valid."))
        XCTAssertTrue(message(Data("<html>bad gateway</html>".utf8),502,.openai).contains("bad gateway"))
        XCTAssertTrue(ReviewAPI.isTemporary(status:429) && ReviewAPI.isTemporary(status:529) && !ReviewAPI.isTemporary(status:400) && !ReviewAPI.isTemporary(status:401))
    }
    func testWaitingStatesAndStatusLine() {
        let a=UUID(),b=UUID(),c=UUID()
        XCTAssertEqual(ReviewProgress.state(a,active:a,pending:[a,b]),.active)
        XCTAssertEqual(ReviewProgress.state(b,active:a,pending:[a,b]),.queued)
        XCTAssertNil(ReviewProgress.state(c,active:a,pending:[a,b]))
        XCTAssertEqual(ReviewProgress.status(model:"Claude Haiku 5.5",number:1,total:1,name:"IMG_1.HEIC",seconds:7),"Waiting for Claude Haiku 5.5 · IMG_1.HEIC · 7 s — Esc stops")
        XCTAssertEqual(ReviewProgress.status(model:"GPT-6.1 Sol",number:2,total:5,name:"IMG_2.HEIC",seconds:75),"Waiting for GPT-6.1 Sol · page 2 of 5 · IMG_2.HEIC · 1 min 15 s — Esc stops")
        XCTAssertEqual(ReviewProgress.status(model:"Gemini 3.8 Flash",number:0,total:3,name:nil,seconds:0),"Waiting for Gemini 3.8 Flash · 0 s — Esc stops")
    }
    func testPreparedImagesAreReducedCopies() throws {
        let photo=try temporaryPhoto(shadedPage(width:3000,height:2000))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:photo);try? FileManager.default.removeItem(at:directory)}
        var page=Page(path:photo.path);page.quad=current
        try ClaudeReview.prepare(page,in:directory)
        let plain=try Imaging.load(directory.appendingPathComponent(ClaudeReview.photoName),maxPixel:4000)
        let marked=try Imaging.load(directory.appendingPathComponent(ClaudeReview.overlayName),maxPixel:4000)
        XCTAssertEqual(plain.width,1568);XCTAssertEqual(marked.width,plain.width);XCTAssertEqual(marked.height,plain.height)
    }
}

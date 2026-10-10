import XCTest
@testable import CropCore
import CoreGraphics
import PDFKit

private let inset=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])

/// A spread on a dark table: two pages of ruled "print" with a fold at `fold` (fraction of the width).
private func spread(width:Int=1200,height:Int=800,fold:Double,lean:Double=0,shadow:Bool=true,print:Bool=true)->CGImage {
    let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w=CGFloat(width),h=CGFloat(height)
    c.setFillColor(CGColor(gray:0.88,alpha:1));c.fill(CGRect(x:0,y:0,width:w,height:h))
    let top=CGFloat(fold-lean/2)*w,bottom=CGFloat(fold+lean/2)*w
    if print {
        c.setFillColor(CGColor(gray:0.15,alpha:1))
        // Vertical strokes with gaps between them, like columns of vertical text, leaving a blank gutter.
        for x in stride(from:CGFloat(0.06)*w,to:CGFloat(0.94)*w,by:14) where abs(x-CGFloat(fold)*w)>0.05*w {c.fill(CGRect(x:x,y:0.1*h,width:5,height:0.8*h))}
    }
    if shadow {
        c.setStrokeColor(CGColor(gray:0.35,alpha:1));c.setLineWidth(6)
        // Bitmap contexts have a bottom-left origin, so the line's top end is at y = height.
        c.move(to:CGPoint(x:top,y:h));c.addLine(to:CGPoint(x:bottom,y:0));c.strokePath()
    }
    return c.makeImage()!
}
private func temporaryPhoto(_ image:CGImage)throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
    try Exporter.encode(image,as:.jpeg,quality:0.95,dpi:nil).write(to:url)
    return url
}

final class ProposalOrderTests:XCTestCase {
    func quad(_ size:Double)->Quad {Quad([Point(0,0),Point(size,0),Point(size,size),Point(0,size)])}
    func testBestFirstThenLargestToSmallest() {
        let list=[Candidate(quad:quad(0.7),score:0.5,source:"small"),Candidate(quad:quad(0.8),score:0.9,source:"best"),Candidate(quad:quad(1),score:0.1,source:"largest"),Candidate(quad:quad(0.9),score:0.6,source:"large")]
        XCTAssertEqual(Candidate.ordered(list).map{$0.source},["best","largest","large","small"])
        XCTAssertTrue(Candidate.ordered([]).isEmpty)
    }
    func testNewDetectionKeepsClaudeProposal() {
        let old=[Candidate(quad:quad(0.8),score:0.7,source:"Edges"),Candidate(quad:quad(0.95),score:0,source:"Claude")]
        let found=[Candidate(quad:quad(0.85),score:0.9,source:"Document"),Candidate(quad:quad(0.7),score:0.4,source:"Edges refined")]
        let merged=Candidate.merging(detected:found,into:old)
        XCTAssertEqual(merged.map{$0.source},["Document","Claude","Edges refined"],"Old detector proposals go; Claude's stays, in size order after the best")
        XCTAssertEqual(merged.first{$0.source=="Claude"}?.quad,quad(0.95))
        XCTAssertEqual(Candidate.merging(detected:[],into:old).map{$0.source},["Claude"],"A detection that finds nothing still keeps Claude's proposal")
        XCTAssertEqual(Candidate.merging(detected:found,into:[]).map{$0.source},["Document","Edges refined"])
    }
}

final class PageSplitTests:XCTestCase {
    func testMovingKeepsTiltAndStopsAtMargins() {
        let split=PageSplit(top:0.48,bottom:0.52)
        let moved=split.moved(by:0.1)
        XCTAssertEqual(moved.top,0.58,accuracy:1e-9);XCTAssertEqual(moved.bottom,0.62,accuracy:1e-9)
        let far=split.moved(by:5)
        XCTAssertEqual(far.bottom,1-PageSplit.margin,accuracy:1e-9);XCTAssertEqual(far.bottom-far.top,0.04,accuracy:1e-9)
        XCTAssertEqual(split.moved(by:-5).top,PageSplit.margin,accuracy:1e-9)
        XCTAssertEqual(PageSplit(top:-3,bottom:.nan).clamped,PageSplit(top:PageSplit.margin,bottom:0.5))
    }
    func testQuarterTurnsDropTheSplitAndHalfTurnsMirrorIt() {
        let split=PageSplit(top:0.4,bottom:0.45)
        XCTAssertNil(split.rotated(quarterTurns:1));XCTAssertNil(split.rotated(quarterTurns:-1));XCTAssertNil(split.rotated(quarterTurns:3))
        let flipped=try! XCTUnwrap(split.rotated(quarterTurns:2))
        XCTAssertEqual(flipped.top,0.55,accuracy:1e-9);XCTAssertEqual(flipped.bottom,0.6,accuracy:1e-9)
        XCTAssertEqual(split.rotated(quarterTurns:0),split);XCTAssertEqual(split.rotated(quarterTurns:4),split)
    }
    func testLineAndPartsOnAnUprightCrop() throws {
        let split=PageSplit(top:0.5,bottom:0.25)
        let line=try XCTUnwrap(SplitGeometry.line(split,quad:inset,rotation:0))
        XCTAssertEqual(line.0.x,0.5,accuracy:1e-9);XCTAssertEqual(line.0.y,0.1,accuracy:1e-9)
        XCTAssertEqual(line.1.x,0.3,accuracy:1e-9);XCTAssertEqual(line.1.y,0.9,accuracy:1e-9)
        let parts=try XCTUnwrap(SplitGeometry.parts(split,quad:inset,rotation:0))
        XCTAssertEqual(parts.count,2);XCTAssertTrue(parts[0].valid && parts[1].valid)
        XCTAssertEqual(parts[0].points[0],inset.points[0]);XCTAssertEqual(parts[0].points[3],inset.points[3])
        XCTAssertEqual(parts[1].points[1],inset.points[1]);XCTAssertEqual(parts[1].points[2],inset.points[2])
        XCTAssertEqual(parts[0].area+parts[1].area,inset.area,accuracy:1e-9)
        let position=try XCTUnwrap(SplitGeometry.position(of:Point(0.3,0.9),quad:inset,rotation:0))
        XCTAssertEqual(position.u,0.25,accuracy:1e-9);XCTAssertEqual(position.v,1,accuracy:1e-9)
    }
    func testRotatedOutputSplitsAcrossThePhotograph() throws {
        // Turned a quarter clockwise, the output's left edge is the photograph's bottom edge.
        let line=try XCTUnwrap(SplitGeometry.line(PageSplit(top:0.25,bottom:0.25),quad:inset,rotation:1))
        XCTAssertEqual(line.0.y,0.7,accuracy:1e-9);XCTAssertEqual(line.1.y,0.7,accuracy:1e-9)
        XCTAssertEqual(line.0.x,0.1,accuracy:1e-9);XCTAssertEqual(line.1.x,0.9,accuracy:1e-9)
        let parts=try XCTUnwrap(SplitGeometry.parts(PageSplit(top:0.25,bottom:0.25),quad:inset,rotation:1))
        XCTAssertTrue(parts[0].valid && parts[1].valid)
        XCTAssertEqual(parts[0].area,inset.area*0.25,accuracy:1e-9,"The output's left quarter is the photograph's bottom quarter")
        XCTAssertEqual(parts[0].points.map{$0.y}.min()!,0.7,accuracy:1e-9)
    }
    func testPerspectiveRoundTrip() throws {
        let skewed=Quad([Point(0.12,0.08),Point(0.93,0.15),Point(0.88,0.9),Point(0.05,0.8)])
        for rotation in 0..<4 {
            let line=try XCTUnwrap(SplitGeometry.line(PageSplit(top:0.37,bottom:0.61),quad:skewed,rotation:rotation))
            let top=try XCTUnwrap(SplitGeometry.position(of:line.0,quad:skewed,rotation:rotation)),bottom=try XCTUnwrap(SplitGeometry.position(of:line.1,quad:skewed,rotation:rotation))
            XCTAssertEqual(top.u,0.37,accuracy:1e-9);XCTAssertEqual(top.v,0,accuracy:1e-9);XCTAssertEqual(bottom.u,0.61,accuracy:1e-9);XCTAssertEqual(bottom.v,1,accuracy:1e-9)
            XCTAssertNotNil(SplitGeometry.parts(PageSplit(top:0.37,bottom:0.61),quad:skewed,rotation:rotation))
        }
    }
    func testSplitSurvivesProjectRoundTripAndOldProjectsHaveNone() throws {
        var page=Page(path:"/photos/a.jpg");page.split=PageSplit(top:0.47,bottom:0.5)
        XCTAssertEqual(try JSONDecoder().decode(Page.self,from:JSONEncoder().encode(page)).split,PageSplit(top:0.47,bottom:0.5))
        XCTAssertNil(Page(path:"/photos/b.jpg").split)
    }
}

final class SplitDetectorTests:XCTestCase {
    func testFindsLeaningFoldAwayFromCentre() throws {
        let proposal=try SplitDetector.detect(spread(fold:0.45,lean:0.03),quad:.full,rotation:0)
        XCTAssertTrue(proposal.confident)
        XCTAssertEqual(proposal.split.top,0.435,accuracy:0.012);XCTAssertEqual(proposal.split.bottom,0.465,accuracy:0.012)
    }
    func testFindsBlankGutterWithoutShadow() throws {
        let proposal=try SplitDetector.detect(spread(fold:0.56,shadow:false),quad:.full,rotation:0)
        XCTAssertTrue(proposal.confident)
        XCTAssertEqual((proposal.split.top+proposal.split.bottom)/2,0.56,accuracy:0.03)
    }
    func testBlankSheetFallsBackToCentre() throws {
        let proposal=try SplitDetector.detect(spread(fold:0.5,shadow:false,print:false),quad:.full,rotation:0)
        XCTAssertFalse(proposal.confident);XCTAssertEqual(proposal.split,.centre)
    }
    func testFoldIsFoundInTheRotatedOutput() throws {
        // Seen a quarter turn clockwise, the fold at 45% of the photograph's width lies at 45% of the output's height,
        // so nothing vertical divides the output and the split falls back to the centre.
        let turned=try SplitDetector.detect(spread(fold:0.45,print:false),quad:.full,rotation:1)
        XCTAssertFalse(turned.confident)
        let flipped=try SplitDetector.detect(spread(fold:0.45,print:false),quad:.full,rotation:2)
        XCTAssertTrue(flipped.confident);XCTAssertEqual(flipped.split.top,0.55,accuracy:0.012)
    }
}

final class SplitExportTests:XCTestCase {
    func testSplitSpreadBecomesTwoPagesInTheChosenOrder() throws {
        let photo=try temporaryPhoto(spread(width:1200,height:900,fold:0.4))
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:photo);try? FileManager.default.removeItem(at:folder)}
        var page=Page(path:photo.path);page.split=PageSplit(top:0.4,bottom:0.4)
        var options=ExportOptions();options.format = .jpeg
        let parts=try Exporter.renderAll(page,options:options)
        XCTAssertEqual(parts.count,2)
        XCTAssertEqual(parts[0].image.width,480,accuracy:3);XCTAssertEqual(parts[1].image.width,720,accuracy:3);XCTAssertEqual(parts[0].image.height,900,accuracy:3)
        XCTAssertEqual(parts[0].layout.dpi,300,accuracy:0.001,"Halves keep the spread's resolution")
        XCTAssertEqual(parts[0].layout.pageSize.width,480.0/300*72,accuracy:1)
        options.splitOrder = .rightFirst
        XCTAssertEqual(try Exporter.renderAll(page,options:options).map{$0.image.width}.first ?? 0,720,accuracy:3)
        options.splitOrder = .ignore
        XCTAssertEqual(try Exporter.renderAll(page,options:options).count,1)
        XCTAssertEqual(try Exporter.render(page,options:ExportOptions()).image.width,1200,accuracy:3,"render is always the whole crop")
        options.splitOrder=nil
        let files=try Exporter.writeImages(page,in:folder,name:"0001-spread",options:options)
        XCTAssertEqual(files.map{$0.lastPathComponent},["0001-spread-1.jpg","0001-spread-2.jpg"])
        XCTAssertEqual(try Imaging.load(files[0],maxPixel:4000).width,480,accuracy:3)
        page.split=nil
        XCTAssertEqual(try Exporter.writeImages(page,in:folder,name:"0002-whole",options:options).map{$0.lastPathComponent},["0002-whole.jpg"])
    }
    func testSplitSpreadMakesTwoPDFPagesAndSizedHalvesShareTheWidth() throws {
        let photo=try temporaryPhoto(spread(width:1200,height:900,fold:0.5))
        let pdf=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
        defer{try? FileManager.default.removeItem(at:photo);try? FileManager.default.removeItem(at:pdf)}
        var page=Page(path:photo.path);page.split = .centre;page.format=PageFormat(widthCM:30)
        let writer=try PDFWriter(url:pdf);try writer.add(page,options:ExportOptions());try writer.add(Page(path:photo.path),options:ExportOptions());writer.close()
        let document=try XCTUnwrap(PDFDocument(url:pdf))
        XCTAssertEqual(document.pageCount,3)
        XCTAssertEqual(try XCTUnwrap(document.page(at:0)).bounds(for:.mediaBox).width,15/2.54*72,accuracy:1.5,"Half of a 30 cm spread is 15 cm wide")
        var fitted=page;fitted.format=PageFormat(fitInto:.a4)
        let half=try Exporter.renderAll(fitted,options:ExportOptions())[0]
        XCTAssertEqual(half.layout.pageSize.width,21.0/2.54*72,accuracy:0.5,"A portrait half goes on a portrait sheet")
    }
    func testSplitOrderIsRememberedAndOldSavedOptionsStillLoad() throws {
        var options=ExportOptions();options.splitOrder = .rightFirst
        XCTAssertEqual(try JSONDecoder().decode(ExportOptions.self,from:JSONEncoder().encode(options)).splitOrder,.rightFirst)
        let old=#"{"format":"pdf","searchableText":false,"jpegQuality":0.85}"#
        XCTAssertNil(try JSONDecoder().decode(ExportOptions.self,from:Data(old.utf8)).splitOrder)
    }
}

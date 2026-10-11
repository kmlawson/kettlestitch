import XCTest
@testable import CropCore
import CoreGraphics

/// Gray rows from the top, 0 black to 1 white: ruled lines of "print" turned clockwise by `degrees` as seen.
private func ruled(width w:Int=400,height h:Int=300,degrees:Double,vertical:Bool=false,pitch:Double=18)->[Double] {
    let t=tan(degrees * .pi/180)
    var g=[Double](repeating:0.9,count:w*h)
    for y in 0..<h {for x in 0..<w where x>30 && x<w-30 && y>30 && y<h-30 {
        // Clockwise as seen with y downward: a horizontal line drops to the right, a vertical one drifts left going down.
        let along=vertical ? Double(x)+Double(y)*t:Double(y)-Double(x)*t
        if along.truncatingRemainder(dividingBy:pitch)<5 {g[y*w+x]=0.12}
    }}
    return g
}
private func image(_ gray:[Double],_ w:Int,_ h:Int)->CGImage {
    let bytes=gray.map{UInt8(max(0,min(255,$0*255)))}
    return CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
private func pixels(_ image:CGImage)->[UInt8] {
    var out=[UInt8](repeating:0,count:image.width*image.height)
    out.withUnsafeMutableBytes{b in CGContext(data:b.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)!.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))}
    return out
}
private func temporaryPhoto(_ image:CGImage)throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
    try Exporter.encode(image,as:.png,quality:1,dpi:nil).write(to:url)
    return url
}
private func page(_ name:String,_ quad:Quad = .full)->Page {var p=Page(path:"/photos/\(name).jpg");p.imageAspectRatio=4.0/3;p.quad=quad;return p}
private func box(_ a:Double,_ b:Double,_ c:Double,_ d:Double)->Quad {Quad([Point(a,b),Point(c,b),Point(c,d),Point(a,d)])}

/// A page as photographed: uneven lighting, characters rather than solid rules, and a dark picture on it.
private func printed(width w:Int=600,height h:Int=450,degrees:Double,vertical:Bool=false,text:Bool=true,picture:Bool=true)->[Double] {
    let t=tan(degrees * .pi/180)
    var g=[Double](repeating:0,count:w*h)
    var seed:UInt64=42
    func noise()->Double {seed=seed &* 6364136223846793005 &+ 1442695040888963407;return Double(seed>>40)/Double(1<<24)}
    for y in 0..<h {for x in 0..<w {g[y*w+x]=0.62+0.28*Double(x)/Double(w)+0.03*(noise()-0.5)}}
    if text {
        for y in 0..<h {for x in 0..<w where x>40 && x<w-40 && y>40 && y<h-40 {
            // Position along and across the lines of text, turned clockwise as seen.
            let across=vertical ? Double(x)+Double(y)*t:Double(y)-Double(x)*t,along=vertical ? Double(y)-Double(x)*t:Double(x)+Double(y)*t
            let line=across.truncatingRemainder(dividingBy:22),character=along.truncatingRemainder(dividingBy:13)
            // Characters 9 wide and 12 tall with gaps, each a different shape so that no stroke runs the whole line.
            if line<12,character<9,noise()<0.55 {g[y*w+x]=0.18}
        }}
    }
    if picture {for y in 150..<300 {for x in 330..<520 {g[y*w+x]=0.12+0.25*noise()}}}
    return g
}

final class RealisticSkewTests:XCTestCase {
    func testFindsTiltOfCharactersOnAShadedPageWithAPicture() {
        for degrees in [2.0,-1.2] {
            let found=SkewDetector.analyse(printed(degrees:degrees),width:600,height:450)
            XCTAssertTrue(found.confident,"\(degrees)");XCTAssertEqual(found.angle,degrees,accuracy:0.25)
        }
        let columns=SkewDetector.analyse(printed(degrees:1.5,vertical:true),width:600,height:450)
        XCTAssertTrue(columns.confident);XCTAssertEqual(columns.angle,1.5,accuracy:0.25)
    }
    func testLevelPrintIsConfidentlyLevelAndAPictureAloneIsUnclear() {
        let level=SkewDetector.analyse(printed(degrees:0),width:600,height:450)
        XCTAssertTrue(level.confident);XCTAssertEqual(level.angle,0,accuracy:0.15)
        XCTAssertFalse(SkewDetector.analyse(printed(degrees:0,text:false),width:600,height:450).confident,"A picture on blank paper has no lines to level")
    }
}

final class SkewDetectorTests:XCTestCase {
    func testFindsTiltOfHorizontalLinesInBothDirections() {
        for degrees in [2.0,-3.5,0.6] {
            let found=SkewDetector.analyse(ruled(degrees:degrees),width:400,height:300)
            XCTAssertTrue(found.confident,"\(degrees)");XCTAssertEqual(found.angle,degrees,accuracy:0.15)
        }
    }
    func testFindsTiltOfVerticalColumns() {
        let found=SkewDetector.analyse(ruled(degrees:-1.8,vertical:true),width:400,height:300)
        XCTAssertTrue(found.confident);XCTAssertEqual(found.angle,-1.8,accuracy:0.15)
    }
    func testLevelPageIsZeroAndBlankPageIsNotConfident() {
        XCTAssertEqual(SkewDetector.analyse(ruled(degrees:0),width:400,height:300).angle,0,accuracy:0.1)
        let blank=SkewDetector.analyse([Double](repeating:0.9,count:400*300),width:400,height:300)
        XCTAssertFalse(blank.confident);XCTAssertEqual(blank.angle,0)
        XCTAssertFalse(SkewDetector.analyse([],width:0,height:0).confident)
    }
    func testDeskewedRenderIsLevel() throws {
        let source=image(ruled(degrees:2.5),400,300)
        XCTAssertEqual(SkewDetector.detect(source).angle,2.5,accuracy:0.2)
        let level=try Imaging.corrected(source,quad:.full,deskew:2.5)
        XCTAssertEqual(level.width,400,accuracy:1);XCTAssertEqual(level.height,300,accuracy:1,"Deskewing keeps the page size")
        XCTAssertEqual(SkewDetector.detect(level).angle,0,accuracy:0.2)
    }
    func testTiltTooSmallToMatterIsLeftAlone() throws {
        func e(_ angle:Double,_ confident:Bool=true)->SkewEstimate {SkewEstimate(angle:angle,confident:confident)}
        XCTAssertNil(SkewDetector.angles(from:[e(0.05)]),"Real level pages measure about 0.05°; turning them would only blur them")
        XCTAssertNil(SkewDetector.angles(from:[e(-0.1),e(0.1)]));XCTAssertNil(SkewDetector.angles(from:[e(3,false)]),"An unclear measurement is never applied")
        XCTAssertEqual(SkewDetector.angles(from:[e(0.1),e(0.6)]),[0,0.6],"Only the page that needs it is turned")
        XCTAssertEqual(SkewDetector.angles(from:[e(-2.8)]),[-2.8]);XCTAssertEqual(SkewDetector.angles(from:[e(2,false),e(-0.15)]),[0,-0.15])
        var p=Page(path:"/nowhere.png")
        XCTAssertNil(try SkewDetector.detect(image(ruled(degrees:0.1),400,300),page:p),"A tenth of a degree is within the measurement's own error")
        XCTAssertEqual(try SkewDetector.detect(image(ruled(degrees:0.6),400,300),page:p)?.first ?? 0,0.6,accuracy:0.15)
        p.split = .centre
        let halves=try XCTUnwrap(try SkewDetector.detect(image(ruled(width:800,height:300,degrees:1),800,300),page:p))
        XCTAssertEqual(halves.count,2);XCTAssertEqual(halves[0],1,accuracy:0.25)
    }
    func testPageStoresOneAnglePerOutputPart() throws {
        var p=page("a")
        XCTAssertEqual(p.deskewAngle(part:0,of:1),0)
        p.deskew=[1.5]
        XCTAssertEqual(p.deskewAngle(part:0,of:1),1.5);XCTAssertEqual(p.deskewAngle(part:0,of:2),0,"An angle found for the whole spread does not apply to its halves")
        p.deskew=[1,-2]
        XCTAssertEqual(p.deskewAngle(part:1,of:2),-2);XCTAssertEqual(p.deskewAngle(part:0,of:1),0)
        XCTAssertEqual(Page.nudged([1,-2],by:0.1,parts:2),[1.1,-1.9]);XCTAssertEqual(Page.nudged(nil,by:-0.1,parts:1),[-0.1])
        XCTAssertEqual(Page.nudged([1.5],by:0.1,parts:2),[0.1,0.1],"A mismatched list starts again from level")
        // On a split spread one half can be turned, levelled or measured while the other is left alone.
        XCTAssertEqual(Page.nudged([1,-2],by:0.1,parts:2,only:1),[1,-1.9]);XCTAssertEqual(Page.nudged(nil,by:0.2,parts:2,only:0),[0.2,0])
        XCTAssertEqual(Page.nudged([1,-2],by:0.1,parts:2,only:5),[1,-2],"A half that is not there turns nothing");XCTAssertEqual(Page.nudged([0.5],by:0.1,parts:1,only:0),[0.6])
        XCTAssertEqual(Page.deskew([1,-2],setting:nil,parts:2,only:0),[0,-2],"One half levelled");XCTAssertNil(Page.deskew([1,0],setting:nil,parts:2,only:0),"Both level means no deskew")
        XCTAssertEqual(Page.deskew([1,-2],setting:[0.4,0.7],parts:2,only:1),[1,0.7],"One half takes its new measurement");XCTAssertEqual(Page.deskew(nil,setting:[0.4,0.7],parts:2,only:0),[0.4,0])
        XCTAssertEqual(Page.deskew([1,-2],setting:nil,parts:2,only:1),[1,0],"An unclear measurement levels only the half asked about")
        XCTAssertEqual(Page.deskew([1,-2],setting:[0.3,0.3],parts:2,only:nil),[0.3,0.3]);XCTAssertNil(Page.deskew([1,-2],setting:nil,parts:2,only:nil))
        XCTAssertEqual(Page.deskew([1.5],setting:[0.4,0.7],parts:2,only:1),[0,0.7],"A list for another number of parts starts again from level")
        XCTAssertEqual(Page.nudged([14.95],by:0.1,parts:1),[15],"Never more than 15 degrees");XCTAssertNil(Page.nudged([0.05],by:-0.05,parts:1),"Level again means no deskew")
        XCTAssertEqual(try JSONDecoder().decode(Page.self,from:JSONEncoder().encode(p)).deskew,[1,-2])
    }
    func testExportAppliesEachHalfsOwnAngle() throws {
        let photo=try temporaryPhoto(image(ruled(width:800,height:300,degrees:2),800,300))
        defer{try? FileManager.default.removeItem(at:photo)}
        var p=Page(path:photo.path);p.split = .centre
        var options=ExportOptions();options.format = .png
        XCTAssertEqual(SkewDetector.detect(try Exporter.renderAll(p,options:options)[0].image).angle,2,accuracy:0.25)
        p.deskew=try SkewDetector.detect(Imaging.load(photo,maxPixel:4000),page:p)
        XCTAssertEqual(p.deskew?.count,2);XCTAssertEqual(p.deskew?[0] ?? 0,2,accuracy:0.25)
        for part in try Exporter.renderAll(p,options:options) {XCTAssertEqual(SkewDetector.detect(part.image).angle,0,accuracy:0.25)}
        options.splitOrder = .rightFirst;p.deskew=[2,0]
        let reversed=try Exporter.renderAll(p,options:options)
        XCTAssertEqual(SkewDetector.detect(reversed[1].image).angle,0,accuracy:0.25,"Angles follow their page when the order is reversed")
        XCTAssertEqual(SkewDetector.detect(reversed[0].image).angle,2,accuracy:0.25)
    }
}

final class PreviewTests:XCTestCase {
    func testPreviewShowsWholeCropOrBothPagesSideBySideWithTheirOwnDeskew() throws {
        let source=image(ruled(width:800,height:300,degrees:2),800,300)
        var p=Page(path:"/nowhere.png");p.deskew=[2]
        let whole=try Exporter.preview(source,page:p)
        XCTAssertEqual(whole.width,800,accuracy:2);XCTAssertEqual(SkewDetector.detect(whole).angle,0,accuracy:0.25,"The preview shows the deskewed result")
        p.split=PageSplit(top:0.25,bottom:0.25);p.deskew=[2,2]
        let both=try Exporter.preview(source,page:p)
        XCTAssertEqual(both.width,800+Exporter.previewGap(between:[800]),accuracy:3,"Two pages with a gap between them");XCTAssertEqual(both.height,300,accuracy:2)
        let row=Array(pixels(both)[150*both.width..<151*both.width])
        let gap=row[200+Exporter.previewGap(between:[800])/2]
        let all=pixels(both)
        XCTAssertLessThan(gap,10,"A black band sits where the split is")
        for y in [10,150,290] {XCTAssertEqual(all[y*both.width+200+Exporter.previewGap(between:[800])/2],gap,accuracy:2,"and runs the full height")}
        // Each page is judged on its own; the band between them is not print.
        let right=try XCTUnwrap(both.cropping(to:CGRect(x:200+Exporter.previewGap(between:[800]),y:0,width:both.width-200-Exporter.previewGap(between:[800]),height:both.height)))
        XCTAssertEqual(SkewDetector.detect(right).angle,0,accuracy:0.3)
        XCTAssertEqual(Exporter.previewParts(p),2);p.split=nil;XCTAssertEqual(Exporter.previewParts(p),1)
    }
}

final class DespeckleTests:XCTestCase {
    /// White sheet with a solid block, a dot touching distance from it, and lone specks of several sizes.
    func sheet()->(pixels:[UInt8],w:Int,h:Int) {
        let w=300,h=200;var p=[UInt8](repeating:255,count:w*h)
        func fill(_ x:Int,_ y:Int,_ s:Int){for j in y..<y+s {for i in x..<x+s {p[j*w+i]=0}}}
        fill(40,40,40)      // print
        fill(84,50,2)       // a small mark beside the print, like a diacritic
        fill(200,30,1)      // lone 1 px speck
        fill(220,100,2)     // lone 2 x 2 speck
        fill(180,150,3)     // lone 3 x 3 speck
        fill(250,160,6)     // lone 6 x 6 blot
        return (p,w,h)
    }
    func black(_ p:[UInt8],_ w:Int,_ x:Int,_ y:Int)->Bool {p[y*w+x]<128}
    func testLevelsRemoveLargerSpecksButNeverPrintOrMarksBesideIt() {
        let s=sheet()
        var off=s.pixels;Despeckle.clean(&off,width:s.w,height:s.h,level:0);XCTAssertEqual(off,s.pixels)
        var cautious=s.pixels;Despeckle.clean(&cautious,width:s.w,height:s.h,level:1)
        XCTAssertFalse(black(cautious,s.w,200,30));XCTAssertTrue(black(cautious,s.w,181,151),"Cautious leaves a 3 x 3 speck")
        var normal=s.pixels;Despeckle.clean(&normal,width:s.w,height:s.h,level:2)
        XCTAssertFalse(black(normal,s.w,220,100));XCTAssertTrue(black(normal,s.w,181,151))
        var aggressive=s.pixels;Despeckle.clean(&aggressive,width:s.w,height:s.h,level:3)
        XCTAssertFalse(black(aggressive,s.w,181,151));XCTAssertTrue(black(aggressive,s.w,252,162),"A 6 x 6 blot is not a speck at any level")
        for result in [cautious,normal,aggressive] {XCTAssertTrue(black(result,s.w,60,60));XCTAssertTrue(black(result,s.w,84,50),"A small mark beside print is part of it")}
    }
    func testLimitGrowsWithResolution() {
        XCTAssertGreaterThan(Despeckle.limit(level:2,longSide:6000),Despeckle.limit(level:2,longSide:1500))
        XCTAssertGreaterThan(Despeckle.limit(level:3,longSide:1500),Despeckle.limit(level:1,longSide:1500))
        XCTAssertEqual(Despeckle.limit(level:0,longSide:6000),0);XCTAssertEqual(Despeckle.limit(level:9,longSide:1500),Despeckle.limit(level:3,longSide:1500))
    }
    func testAppliedOnlyToBlackAndWhiteOutput() throws {
        var g=[Double](repeating:0.85,count:400*300)
        // A stroke of print, thin enough that cleanup does not take its inside for paper.
        for y in 148..<156 {for x in 100..<300 {g[y*400+x]=0.1}}
        // A 2 x 2 speck; rendering resamples it, so look at its neighbourhood rather than one pixel.
        for y in 30..<32 {for x in 350..<352 {g[y*400+x]=0.05}}
        let source=image(g,400,300)
        func darkest(_ p:[UInt8])->UInt8 {var m=UInt8(255);for y in 27..<35 {for x in 347..<355 {m=min(m,p[y*400+x])}};return m}
        var a=Adjustments();a.cleanup = .blackAndWhite
        XCTAssertLessThan(darkest(pixels(try Imaging.corrected(source,quad:.full,adjustments:a))),128,"Without despeckle the speck is there")
        a.despeckle=3
        let cleaned=pixels(try Imaging.corrected(source,quad:.full,adjustments:a))
        XCTAssertGreaterThan(darkest(cleaned),128);XCTAssertLessThan(cleaned[152*400+200],128)
        var gray=Adjustments();gray.cleanup = .grayscale;gray.despeckle=3
        XCTAssertLessThan(darkest(pixels(try Imaging.corrected(source,quad:.full,adjustments:gray))),200,"Grayscale output is not despeckled")
        var none=Adjustments();none.despeckle=0;XCTAssertNotEqual(none,Adjustments());none.despeckle=nil;XCTAssertTrue(none.isIdentity)
        let old=#"{"cleanup":"blackAndWhite","brightness":0.1,"contrast":0}"#
        XCTAssertNil(try JSONDecoder().decode(Adjustments.self,from:Data(old.utf8)).despeckle,"Projects saved before despeckle existed still open")
    }
}

final class PictureZoneTests:XCTestCase {
    func testZoneIsNormalisedClampedAndNeedsSomeSize() {
        let z=PictureZone(from:(0.8,0.9),to:(0.2,-0.3))
        XCTAssertEqual(z.minU,0.2);XCTAssertEqual(z.maxU,0.8);XCTAssertEqual(z.minV,0);XCTAssertEqual(z.maxV,0.9);XCTAssertTrue(z.isUsable)
        XCTAssertFalse(PictureZone(from:(0.5,0.5),to:(0.505,0.9)).isUsable,"A sliver is a slip of the mouse")
        XCTAssertTrue(z.contains(0.5,0.5));XCTAssertFalse(z.contains(0.1,0.5))
    }
    func testZoneOutlineFollowsTheCropOnThePhotograph() throws {
        let crop=box(0.1,0.1,0.9,0.9),zone=PictureZone(from:(0.25,0.5),to:(0.75,1))
        let outline=try XCTUnwrap(zone.outline(quad:crop,rotation:0))
        XCTAssertEqual(outline[0].x,0.3,accuracy:1e-9);XCTAssertEqual(outline[0].y,0.5,accuracy:1e-9);XCTAssertEqual(outline[2].x,0.7,accuracy:1e-9);XCTAssertEqual(outline[2].y,0.9,accuracy:1e-9)
        let turned=try XCTUnwrap(zone.outline(quad:crop,rotation:1))
        // Turned a quarter clockwise, the photograph's left edge is the output's top, so the output's lower half is the photograph's right half.
        XCTAssertEqual(turned.map{$0.y}.min()!,0.3,accuracy:1e-9);XCTAssertEqual(turned.map{$0.y}.max()!,0.7,accuracy:1e-9)
        XCTAssertEqual(turned.map{$0.x}.min()!,0.5,accuracy:1e-9);XCTAssertEqual(turned.map{$0.x}.max()!,0.9,accuracy:1e-9)
    }
    func testBlackAndWhitePageKeepsTonesInsideAZone() throws {
        // Left half mid-gray "photograph", right half pale paper with one dark bar.
        var g=[Double](repeating:0.85,count:400*300)
        for y in 0..<300 {for x in 0..<200 {g[y*400+x]=0.35+0.3*Double(y)/300}}
        for y in 100..<200 {for x in 280..<300 {g[y*400+x]=0.1}}
        let photo=try temporaryPhoto(image(g,400,300))
        defer{try? FileManager.default.removeItem(at:photo)}
        var p=Page(path:photo.path);var a=Adjustments();a.cleanup = .blackAndWhite;p.adjustments=a
        var options=ExportOptions();options.format = .png
        let plain=try Exporter.render(p,options:options)
        XCTAssertEqual(plain.image.bitsPerPixel,1,"Without zones the page is a one-bit image")
        p.pictureZones=[PictureZone(from:(0,0),to:(0.5,1))]
        let before=Imaging.pictureZoneMode;defer{Imaging.pictureZoneMode=before};Imaging.pictureZoneMode = .grayscale
        let mixed=try Exporter.render(p,options:options)
        XCTAssertEqual(mixed.image.bitsPerPixel,8,"A page with a picture needs gray levels")
        let out=pixels(mixed.image),w=mixed.image.width
        let top=out[40*w+100],bottom=out[260*w+100]
        XCTAssertTrue(top>40 && top<215 && bottom>40 && bottom<215,"Inside the zone the tones survive: \(top) \(bottom)");XCTAssertGreaterThan(Int(bottom)-Int(top),25)
        XCTAssertGreaterThan(out[40*w+350],250);XCTAssertLessThan(out[150*w+290],5,"Outside it the page is pure black and white")
        var gray=p;gray.adjustments?.cleanup = .grayscale
        XCTAssertEqual(try Exporter.render(gray,options:options).image.bitsPerPixel,8,"Zones change nothing in other modes")
    }
    func testPictureZonesAreRenderedInTheModeChosenInSettings() throws {
        // A reddish "picture" on the left of pale paper, with one dark bar of print on the right.
        let w=400,h=300
        let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red:0.85,green:0.85,blue:0.85,alpha:1));c.fill(CGRect(x:0,y:0,width:w,height:h))
        c.setFillColor(CGColor(red:0.7,green:0.3,blue:0.25,alpha:1));c.fill(CGRect(x:0,y:0,width:200,height:h))
        c.setFillColor(CGColor(gray:0.1,alpha:1));c.fill(CGRect(x:280,y:100,width:20,height:100))
        let photo=try temporaryPhoto(c.makeImage()!);defer{try? FileManager.default.removeItem(at:photo)}
        var p=Page(path:photo.path);var a=Adjustments();a.cleanup = .blackAndWhite;p.adjustments=a
        p.pictureZones=[PictureZone(from:(0,0),to:(0.5,1))]
        var options=ExportOptions();options.format = .png
        /// Red, green and blue at a pixel of the rendered page, whatever its depth.
        func colour(_ image:CGImage,_ x:Int,_ y:Int)->(Int,Int,Int) {
            var px=[UInt8](repeating:0,count:4)
            let one=CGContext(data:&px,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            one.draw(image,in:CGRect(x:-x,y:-(image.height-1-y),width:image.width,height:image.height))
            return (Int(px[0]),Int(px[1]),Int(px[2]))
        }
        let before=Imaging.pictureZoneMode;defer{Imaging.pictureZoneMode=before}
        XCTAssertEqual(before,.grayscale,"Gray is the setting until another is chosen")
        // No mode: the picture is left exactly as photographed, whatever the page's settings, on a black-and-white page.
        Imaging.pictureZoneMode = .none
        let asTaken=colour(try Exporter.render(p,options:options).image,100,150)
        p.adjustments?.brightness=0.3
        let untouched=try Exporter.render(p,options:options).image
        let red=colour(untouched,100,150);XCTAssertGreaterThan(red.0-red.2,60,"The picture keeps its colour: \(red)")
        XCTAssertEqual(red.0,asTaken.0,accuracy:2,"and is the same whatever the page's brightness")
        let paper=colour(untouched,350,40),bar=colour(untouched,290,150)
        XCTAssertGreaterThan(paper.0,250);XCTAssertLessThan(bar.0,5,"Outside the zone the page is pure black and white")
        // Colour: in colour too, but with the page's brightness, here raised.
        Imaging.pictureZoneMode = .color
        let coloured=colour(try Exporter.render(p,options:options).image,100,150);XCTAssertGreaterThan(coloured.0-coloured.2,30,"\(coloured)")
        XCTAssertGreaterThan(coloured.0,red.0+10,"The page's brightness applies: \(coloured) against \(red)")
        // Grayscale: gray tones, in an image that holds no colour.
        Imaging.pictureZoneMode = .grayscale
        let gray=try Exporter.render(p,options:options).image
        XCTAssertEqual(gray.bitsPerPixel,8);let tone=colour(gray,100,150);XCTAssertLessThan(abs(tone.0-tone.2),3,"\(tone)")
        XCTAssertLessThan(colour(gray,290,150).0,5)
    }
    func testZoneStaysOnItsPictureWhenThePageIsSplit() throws {
        var g=[Double](repeating:0.85,count:800*300)
        for y in 50..<250 {for x in 450..<750 {g[y*800+x]=0.5}}
        let photo=try temporaryPhoto(image(g,800,300))
        defer{try? FileManager.default.removeItem(at:photo)}
        var p=Page(path:photo.path);var a=Adjustments();a.cleanup = .blackAndWhite;p.adjustments=a;p.split = .centre
        p.pictureZones=[PictureZone(from:(0.55,0.1),to:(0.95,0.9))]
        var options=ExportOptions();options.format = .png
        let before=Imaging.pictureZoneMode;defer{Imaging.pictureZoneMode=before};Imaging.pictureZoneMode = .grayscale
        let parts=try Exporter.renderAll(p,options:options)
        XCTAssertEqual(parts[0].image.bitsPerPixel,1,"The left page has no picture and stays one-bit")
        XCTAssertEqual(parts[1].image.bitsPerPixel,8)
        let right=pixels(parts[1].image),w=parts[1].image.width
        let inside=right[150*w+200];XCTAssertTrue(inside>90 && inside<170,"\(inside)")
        XCTAssertEqual(try JSONDecoder().decode(Page.self,from:JSONEncoder().encode(p)).pictureZones,p.pictureZones)
    }
}

final class DeviationTests:XCTestCase {
    func testRobustScoresIgnoreTheOutlierWhenSettingTheScale() {
        let scores=Deviation.robustScores([10,10.1,9.9,10,10.2,9.8,14,nil],floor:0.05)
        XCTAssertGreaterThan(scores[6],Deviation.threshold);for i in 0..<6 {XCTAssertLessThan(scores[i],Deviation.threshold)}
        XCTAssertEqual(scores[7],0,"A page without the measurement is not an outlier")
        XCTAssertEqual(Deviation.robustScores([5,5,5,5],floor:0.1),[0,0,0,0]);XCTAssertTrue(Deviation.robustScores([],floor:1).isEmpty)
        XCTAssertLessThan(Deviation.robustScores([5,5,5,5.01],floor:0.1)[3],1,"The floor keeps trivial differences from looking large")
    }
    func project()->[Page] {
        var pages=(0..<12).map{page("p\($0)",box(0.05+Double($0%3)*0.004,0.05,0.95,0.95))}
        pages[4].quad=box(0.3,0.3,0.7,0.7)                                                     // far too small
        pages[7].quad=Quad([Point(0.05,0.05),Point(0.95,0.25),Point(0.95,0.75),Point(0.05,0.95)]) // strongly tapered
        pages[9].deskew=[6];for i in [0,1,2,3] {pages[i].deskew=[0.2]}                           // unusually skewed
        return pages
    }
    func testReportNamesWhatIsUnusualAboutAPage() {
        let rows=Deviation.report(project())
        XCTAssertEqual(rows.count,12);XCTAssertEqual(rows.map{$0.index},Array(0..<12))
        XCTAssertEqual(rows[4].reason,"size");XCTAssertTrue(rows[4].isOutlier)
        XCTAssertEqual(rows[7].reason,"taper");XCTAssertEqual(rows[9].reason,"skew")
        XCTAssertFalse(rows[0].isOutlier);XCTAssertNil(rows[0].reason)
        XCTAssertEqual(rows.filter{$0.isOutlier}.map{$0.index},[4,7,9])
    }
    func testSortingByAMeasurePutsTheWorstFirstAndPageOrderRestoresIt() {
        let rows=Deviation.report(project())
        XCTAssertEqual(Deviation.sorted(rows,by:.size,descending:true).first?.index,4)
        XCTAssertEqual(Deviation.sorted(rows,by:.taper,descending:true).first?.index,7)
        XCTAssertEqual(Deviation.sorted(rows,by:.skew,descending:true).first?.index,9)
        XCTAssertEqual(Set(Deviation.sorted(rows,by:.worst,descending:true).prefix(3).map{$0.index}),[4,7,9])
        XCTAssertEqual(Deviation.sorted(Deviation.sorted(rows,by:.worst,descending:true),by:.page,descending:false).map{$0.index},Array(0..<12))
        XCTAssertEqual(Deviation.nextOutlier(after:4,in:rows),7);XCTAssertEqual(Deviation.nextOutlier(after:9,in:rows),4,"Wraps round");XCTAssertNil(Deviation.nextOutlier(after:0,in:Deviation.report([page("x"),page("y")])))
    }
    func testFewPagesOrMissingPhotographsGiveNoFalseAlarms() {
        XCTAssertTrue(Deviation.report([page("a"),page("b",box(0.3,0.3,0.7,0.7))]).allSatisfy{!$0.isOutlier},"Two pages cannot define what is usual")
        var missing=page("gone");missing.imageAspectRatio=nil
        XCTAssertFalse(Deviation.report((0..<8).map{page("p\($0)")}+[missing]).last!.isOutlier)
    }
}

final class NewCommandTests:XCTestCase {
    func state(_ change:(inout MenuState)->Void={_ in})->MenuState {var s=MenuState();s.pageCount=10;s.current=3;s.targetCount=1;change(&s);return s}
    func testNewCommandsNeedTheirSubject() {
        XCTAssertTrue(MenuPolicy.isEnabled(.deskew,state()));XCTAssertFalse(MenuPolicy.isEnabled(.deskew,MenuState()))
        XCTAssertFalse(MenuPolicy.isEnabled(.removeDeskew,state()));XCTAssertTrue(MenuPolicy.isEnabled(.removeDeskew,state{$0.targetsHaveDeskew=true}))
        XCTAssertTrue(MenuPolicy.isEnabled(.deskewClockwise,state()));XCTAssertTrue(MenuPolicy.isEnabled(.deskewCounterclockwise,state()))
        XCTAssertTrue(MenuPolicy.isEnabled(.addPictureZone,state()));XCTAssertFalse(MenuPolicy.isEnabled(.addPictureZone,state{$0.editingText=true}))
        XCTAssertFalse(MenuPolicy.isEnabled(.removePictureZones,state()));XCTAssertTrue(MenuPolicy.isEnabled(.removePictureZones,state{$0.targetsHaveZones=true}))
        XCTAssertTrue(MenuPolicy.isEnabled(.showDeviations,state()));XCTAssertFalse(MenuPolicy.isEnabled(.showDeviations,MenuState()))
        XCTAssertFalse(MenuPolicy.isEnabled(.nextOutlier,state()));XCTAssertTrue(MenuPolicy.isEnabled(.nextOutlier,state{$0.outlierCount=2}))
        XCTAssertEqual(MenuPolicy.title(.deskew,state{$0.targetCount=5}),"Deskew 5 Pages")
    }
    func testShortcutReferenceListsThem() {
        let all=ShortcutReference.sections.flatMap{$0.entries}
        for expected in ["t","Shift T","Option , / .","w","Shift W","."] {XCTAssertTrue(all.contains{$0.keys==expected},"Missing \(expected)")}
    }
}

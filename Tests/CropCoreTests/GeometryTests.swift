import XCTest
@testable import CropCore
import CoreGraphics
final class GeometryTests:XCTestCase {
    func testCropScaling() throws {
        let q=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
        let grown=try XCTUnwrap(q.scaled(by:1.02))
        XCTAssertEqual(grown.area,q.area*1.02*1.02,accuracy:1e-10)
        XCTAssertLessThan(try XCTUnwrap(grown.scaled(by:1/1.02)).distance(q),1e-10)
        XCTAssertEqual(Quad.full.scaled(by:1.02),Quad.full)
        XCTAssertTrue(try XCTUnwrap(q.scaled(by:10)).valid)
        XCTAssertNil(q.scaled(by:0))
    }
    func testRejectCrossedDegenerateAndOutside(){
        XCTAssertTrue(Quad.full.valid)
        XCTAssertFalse(Quad([Point(0,0),Point(1,1),Point(1,0),Point(0,1)]).valid)
        XCTAssertFalse(Quad([Point(0,0),Point(0,0),Point(0,0),Point(0,0)]).valid)
        XCTAssertFalse(Quad([Point(-0.1,0),Point(1,0),Point(1,1),Point(0,1)]).valid)
        XCTAssertFalse(Quad([]).valid)
    }
    func testProjectRoundTrip300() throws {
        var project=Project();project.pages=(0..<300).map{Page(path:"/photos/\($0).jpg")}
        project.pages[123].quad=Quad([Point(0.1,0.2),Point(0.8,0.1),Point(0.9,0.9),Point(0.1,0.8)])
        project.pages[123].reviewed=true
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:url)}
        try project.save(url);let recovered=try Project.read(url)
        XCTAssertEqual(recovered.pages.count,300);XCTAssertEqual(recovered.pages[123].quad,project.pages[123].quad);XCTAssertTrue(recovered.pages[123].reviewed)
    }
    func testRectificationAndRotation() throws {
        let c=CGContext(data:nil,width:400,height:300,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:400,height:300))
        let image=c.makeImage()!
        let q=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
        let result=try Imaging.corrected(image,quad:q),rotated=try Imaging.corrected(image,quad:q,rotation:1)
        XCTAssertEqual(result.width,320,accuracy:2);XCTAssertEqual(result.height,240,accuracy:2)
        XCTAssertEqual(rotated.width,result.height);XCTAssertEqual(rotated.height,result.width)
    }
}

final class DetectorTests:XCTestCase {
    func testIllustrationDoesNotReplaceWholeSpread() throws {
        let c=CGContext(data:nil,width:1200,height:900,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red:0.5,green:0.37,blue:0.2,alpha:1));c.fill(CGRect(x:0,y:0,width:1200,height:900))
        c.setFillColor(CGColor(gray:0.86,alpha:1));c.fill(CGRect(x:60,y:70,width:1080,height:770))
        c.setFillColor(CGColor(gray:0.12,alpha:1));c.beginPath();c.move(to:CGPoint(x:100,y:120));c.addLine(to:CGPoint(x:1050,y:760));c.addLine(to:CGPoint(x:180,y:760));c.closePath();c.fillPath()
        let candidates=try Detector().detect(c.makeImage()!)
        let best=try XCTUnwrap(candidates.first)
        XCTAssertGreaterThan(best.quad.area,0.70,"A large printed illustration must not replace the spread")
        XCTAssertLessThan(best.quad.distance(Quad([Point(0.05,60.0/900),Point(0.95,60.0/900),Point(0.95,830.0/900),Point(0.05,830.0/900)])),0.035)
    }
}

final class ProposalPolicyTests: XCTestCase {
    func testAreaThresholdAndUserExamples() {
        let atLimit=Quad([Point(0,0),Point(1,0),Point(1,0.65),Point(0,0.65)])
        XCTAssertTrue(ProposalPolicy.accepts(atLimit,imageAspectRatio:4.0/3))
        let small=Quad([Point(0,0),Point(1,0),Point(1,0.649),Point(0,0.649)])
        XCTAssertFalse(ProposalPolicy.accepts(small,imageAspectRatio:4.0/3))
        let diagonal=Quad([Point(0.04,0.70),Point(0.93,0.03),Point(0.97,0.91),Point(0.04,0.93)])
        let halfPage=Quad([Point(0.41,0.02),Point(0.93,0.02),Point(0.97,0.91),Point(0.54,0.92)])
        XCTAssertFalse(ProposalPolicy.accepts(diagonal,imageAspectRatio:4.0/3))
        XCTAssertFalse(ProposalPolicy.accepts(halfPage,imageAspectRatio:4.0/3))
    }
    func testLargeSkewRejectedButModeratePerspectiveAllowed() {
        let skew=Quad([Point(0,0.3),Point(1,0),Point(1,1),Point(0,1)])
        XCTAssertGreaterThan(skew.area,0.65)
        XCTAssertFalse(ProposalPolicy.accepts(skew,imageAspectRatio:4.0/3))
        let normal=Quad([Point(0.06,0.08),Point(0.94,0.04),Point(0.96,0.93),Point(0.04,0.95)])
        XCTAssertTrue(ProposalPolicy.accepts(normal,imageAspectRatio:4.0/3))
    }
    func testSavedProposalsFilteredWithoutChangingManualOrReviewedCrops() {
        let small=Quad([Point(0,0),Point(0.5,0),Point(0.5,1),Point(0,1)])
        var page=Page(path:"/missing.jpg");page.imageAspectRatio=4.0/3
        page.quad=small;page.status="Proposal selected"
        page.candidates=[Candidate(quad:small,score:1,source:"bad"),Candidate(quad:.full,score:0.5,source:"good")]
        var manual=page;manual.status="Manual"
        var reviewed=page;reviewed.reviewed=true
        page.filterProposals();manual.filterProposals();reviewed.filterProposals()
        XCTAssertEqual(page.candidates.count,1);XCTAssertEqual(page.quad,.full)
        XCTAssertEqual(manual.quad,small);XCTAssertEqual(reviewed.quad,small)
        page.candidates=[];page.quad=small;page.status="Check proposal";page.filterProposals()
        XCTAssertEqual(page.quad,.full);XCTAssertEqual(page.status,"No suitable proposal — crop manually")
    }
}

final class EdgeMovementTests:XCTestCase {
    func testOnlyTwoEndpointsMoveTogetherAndClampTogether() throws {
        let q=Quad([Point(0.1,0.1),Point(0.9,0.15),Point(0.9,0.9),Point(0.1,0.9)])
        let moved=try XCTUnwrap(q.movingEdge(0,by:Point(0.03,0.1)))
        XCTAssertEqual(moved.points[0].x-q.points[0].x,moved.points[1].x-q.points[1].x,accuracy:1e-10)
        XCTAssertEqual(moved.points[0].y-q.points[0].y,moved.points[1].y-q.points[1].y,accuracy:1e-10)
        XCTAssertEqual(moved.points[2],q.points[2]);XCTAssertEqual(moved.points[3],q.points[3])
        let clamped=try XCTUnwrap(q.movingEdge(0,by:Point(0,-0.5)))
        XCTAssertEqual(clamped.points[0].y,0,accuracy:1e-10)
        XCTAssertEqual(clamped.points[1].y,0.05,accuracy:1e-10)
        XCTAssertNil(q.movingEdge(0,by:Point(0,0.9)),"Moving an edge through the opposite edge must be rejected")
    }
}

final class MaterialTests:XCTestCase {
    func testBackgroundContaminationAndIsolatedPrint() throws {
        let c=try XCTUnwrap(CGContext(data:nil,width:400,height:300,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setFillColor(CGColor(red:0.45,green:0.32,blue:0.20,alpha:1));c.fill(CGRect(x:0,y:0,width:400,height:300))
        for y in stride(from:0,to:300,by:2) {for x in stride(from:0,to:400,by:2) {
            let shade:CGFloat=(x+y)%4==0 ? 0.08:-0.08
            c.setFillColor(CGColor(red:0.45+shade,green:0.32+shade,blue:0.20+shade,alpha:1));c.fill(CGRect(x:x,y:y,width:2,height:2))
        }}
        c.setFillColor(CGColor(gray:0.9,alpha:1));c.fill(CGRect(x:30,y:25,width:340,height:250))
        // Identical brown artwork within the page is not connected to the outside.
        c.setFillColor(CGColor(red:0.45,green:0.32,blue:0.20,alpha:1));c.fill(CGRect(x:140,y:100,width:100,height:80))
        let material=BackgroundMaterial(try XCTUnwrap(c.makeImage()))
        XCTAssertTrue(material.isBackground(0.02,0.02))
        XCTAssertFalse(material.isBackground(0.45,0.5))
        let page=Quad([Point(0.075,25.0/300),Point(0.925,25.0/300),Point(0.925,275.0/300),Point(0.075,275.0/300)])
        XCTAssertLessThan(material.contamination(page),0.025)
        XCTAssertGreaterThan(material.contamination(.full),0.20)
    }
}

final class PerspectiveRankingTests: XCTestCase {
    func testOneSidedPerspectiveAndCameraRotation() {
        let uneven=Quad([Point(0.07,0.063),Point(0.865,0.032),Point(0.983,0.935),Point(0.077,0.959)])
        let aspect=4.0/3
        XCTAssertGreaterThan(ProposalPolicy.unevenPerspectivePenalty(uneven,imageAspectRatio:aspect),0.15)
        let balanced=Quad([Point(0.14,0.05),Point(0.86,0.05),Point(0.95,0.95),Point(0.05,0.95)])
        XCTAssertEqual(ProposalPolicy.unevenPerspectivePenalty(balanced,imageAspectRatio:aspect),0,accuracy:1e-9)
        XCTAssertEqual(ProposalPolicy.unevenPerspectivePenalty(.full,imageAspectRatio:aspect),0)
        let theta=0.04
        let rotated=Quad(uneven.points.map {p in
            let x=(p.x-0.5)*aspect,y=p.y-0.5
            return Point((x*cos(theta)-y*sin(theta))/aspect+0.5,x*sin(theta)+y*cos(theta)+0.5)
        })
        XCTAssertTrue(rotated.valid)
        XCTAssertEqual(ProposalPolicy.unevenPerspectivePenalty(rotated,imageAspectRatio:aspect),ProposalPolicy.unevenPerspectivePenalty(uneven,imageAspectRatio:aspect),accuracy:1e-9)
    }
}

final class AngleLockedCornerTests: XCTestCase {
    func testAllCornersKeepSideDirectionsAndOppositeCorner() throws {
        let original=Quad([Point(0.15,0.15),Point(0.8,0.1),Point(0.9,0.85),Point(0.1,0.9)])
        for corner in 0..<4 {
            let target=Point(original.points[corner].x+0.02,original.points[corner].y+0.015)
            let moved=try XCTUnwrap(original.movingCornerPreservingAngles(corner,to:target))
            XCTAssertEqual(moved.points[corner],target)
            XCTAssertEqual(moved.points[(corner+2)%4],original.points[(corner+2)%4])
            for i in 0..<4 {
                let a=original.points[i],b=original.points[(i+1)%4],c=moved.points[i],d=moved.points[(i+1)%4]
                XCTAssertEqual((b.x-a.x)*(d.y-c.y)-(b.y-a.y)*(d.x-c.x),0,accuracy:1e-10)
                XCTAssertGreaterThan((b.x-a.x)*(d.x-c.x)+(b.y-a.y)*(d.y-c.y),0)
            }
        }
        XCTAssertNil(original.movingCornerPreservingAngles(0,to:Point(-0.2,-0.2)))
        XCTAssertNil(original.movingCornerPreservingAngles(0,to:Point(0.95,0.95)))
    }
}

final class CropTranslationTests: XCTestCase {
    func testTranslationClampsAllCornersTogether() throws {
        let original=Quad([Point(0.15,0.15),Point(0.8,0.1),Point(0.9,0.85),Point(0.1,0.9)])
        for delta in [Point(-0.5,0),Point(0.5,0),Point(0,-0.5),Point(0,0.5)] {
            let moved=try XCTUnwrap(original.translated(by:delta))
            let dx=moved.points[0].x-original.points[0].x,dy=moved.points[0].y-original.points[0].y
            for i in 1..<4 {
                XCTAssertEqual(moved.points[i].x-original.points[i].x,dx,accuracy:1e-10)
                XCTAssertEqual(moved.points[i].y-original.points[i].y,dy,accuracy:1e-10)
            }
            XCTAssertEqual(moved.area,original.area,accuracy:1e-10)
        }
    }
}

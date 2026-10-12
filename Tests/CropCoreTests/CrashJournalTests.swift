import XCTest
@testable import CropCore

/// What the app writes down as it works, so that a launch after a crash knows what was under way.
final class CrashJournalTests: XCTestCase {
    var support: URL!
    override func setUpWithError() throws {
        support=FileManager.default.temporaryDirectory.appendingPathComponent("journal-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)
    }
    override func tearDown() {Imaging.release();Imaging.readingChanged=nil;try? FileManager.default.removeItem(at:support)}
    func testAJournalLeftBehindMeansTheLastRunDidNotEndWell() throws {
        XCTAssertNil(CrashJournal.read(in:support),"A clean start has none")
        var journal=CrashJournal();journal.project="/books/Atlas.kettlestitch";journal.activity="Exporting";journal.partialExport="/out/.partial-1.pdf";journal.exportDestination="/out/Atlas.pdf";journal.reading=["/photos/b.jpg","/photos/a.jpg","/photos/b.jpg"]
        try journal.write(in:support)
        XCTAssertEqual(CrashJournal.read(in:support),journal)
        XCTAssertEqual(journal.suspects,["/photos/a.jpg","/photos/b.jpg"])
        CrashJournal.clear(in:support);XCTAssertNil(CrashJournal.read(in:support),"A clean quit removes it")
        try Data("{ torn".utf8).write(to:support.appendingPathComponent(CrashJournal.fileName))
        XCTAssertEqual(CrashJournal.read(in:support),CrashJournal(),"A journal torn by the crash itself still says there was one")
    }
    func testTheAccountOfACrashSaysWhatWasLostAndWhatWasKept() {
        var journal=CrashJournal()
        XCTAssertTrue(journal.account(recoverable:0).isEmpty,"Nothing was under way, nothing to tell")
        journal.project="/books/Atlas.kettlestitch"
        XCTAssertTrue(journal.account(recoverable:1).contains{$0.contains("Atlas") && $0.contains("Recovery")})
        journal.activity="Exporting";journal.exportDestination="/out/Atlas.pdf";journal.partialExport="/out/.partial-1.pdf"
        XCTAssertTrue(journal.account(recoverable:0).contains{$0.contains("Atlas.pdf") && $0.contains("did not finish")})
        journal.partialExport=nil;journal.exportDestination="/out/KettleStitch-2026";XCTAssertTrue(journal.account(recoverable:0).contains{$0.contains("KettleStitch-2026") && $0.contains("some")})
        journal.exportDestination=nil;journal.activity="Proposing crops";XCTAssertTrue(journal.account(recoverable:0).contains{$0.contains("Proposing crops")})
        journal.reading=["/photos/a.jpg"];XCTAssertTrue(journal.account(recoverable:0).contains{$0.contains("a.jpg") && $0.contains("set aside")})
    }
    func testAPhotographSetAsideIsNotReadUntilReleased() throws {
        let w=40,h=30,c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:0.5,alpha:1));c.fill(CGRect(x:0,y:0,width:w,height:h))
        let photo=support.appendingPathComponent("a.png");try Exporter.encode(c.makeImage()!,as:.png,quality:1,dpi:nil).write(to:photo)
        XCTAssertNoThrow(try Imaging.load(photo,maxPixel:40))
        Imaging.hold([photo.path]);XCTAssertTrue(Imaging.isHeld(photo.path));XCTAssertEqual(Imaging.heldCount,1)
        XCTAssertThrowsError(try Imaging.load(photo,maxPixel:40)){XCTAssertTrue($0.localizedDescription.contains("set aside"),$0.localizedDescription)}
        Imaging.release();XCTAssertFalse(Imaging.isHeld(photo.path));XCTAssertNoThrow(try Imaging.load(photo,maxPixel:40))
    }
    func testEveryReadIsNotedWhileItLastsAndStruckOffAfter() throws {
        let w=40,h=30,c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let photo=support.appendingPathComponent("b.png");try Exporter.encode(c.makeImage()!,as:.png,quality:1,dpi:nil).write(to:photo)
        var seen:[[String]]=[]
        Imaging.readingChanged={seen.append($0)}
        _=try Imaging.load(photo,maxPixel:40)
        XCTAssertEqual(seen,[[photo.path],[]],"Noted before the read, struck off after")
        // A read that fails in the ordinary way is struck off too.
        seen=[];XCTAssertThrowsError(try Imaging.load(support.appendingPathComponent("absent.png"),maxPixel:40))
        XCTAssertEqual(seen.last,[])
    }
}

import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import CropCore

/// A photograph cut short on its way to the disk still opens, with ImageIO reporting it complete and filling what
/// is missing with gray or black. It must be refused, not cropped and exported.
final class TruncationTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws {
        folder=FileManager.default.temporaryDirectory.appendingPathComponent("truncation-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    }
    override func tearDown() {try? FileManager.default.removeItem(at:folder)}
    /// A picture busy enough that its file is large: bands of colour with noise over them.
    func picture() -> CGImage {
        let w=900,h=700;var px=[UInt8](repeating:255,count:w*h*4);var seed:UInt64=7
        for i in 0..<w*h {seed=seed &* 6364136223846793005 &+ 1442695040888963407;let n=UInt8(truncatingIfNeeded:seed>>40)/3
            px[i*4]=UInt8((i/w)*255/h)/2+n;px[i*4+1]=UInt8((i%w)*255/w)/2+n;px[i*4+2]=n*2}
        return px.withUnsafeMutableBytes{CGContext(data:$0.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!}
    }
    func write(_ type: UTType, _ name: String) throws -> URL {
        let url=folder.appendingPathComponent(name)
        let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,type.identifier as CFString,1,nil),"This Mac cannot write \(type.identifier)")
        CGImageDestinationAddImage(destination,picture(),[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination));return url
    }
    func cut(_ url: URL, to share: Double) throws -> URL {
        let data=try Data(contentsOf:url),short=folder.appendingPathComponent("cut-\(Int(share*100))-"+url.lastPathComponent)
        try data.prefix(Int(Double(data.count)*share)).write(to:short);return short
    }
    func testAPhotographCutShortIsRefusedInEveryFormat() throws {
        for (type,name) in [(UTType.jpeg,"a.jpg"),(.png,"a.png"),(.heic,"a.heic"),(.tiff,"a.tiff")] {
            let whole=try write(type,name)
            XCTAssertNil(Imaging.incomplete(whole),"\(name) is whole");XCTAssertNoThrow(try Imaging.load(whole,maxPixel:400),name)
            for share in [0.25,0.5,0.9,0.99] {
                let short=try cut(whole,to:share)
                XCTAssertThrowsError(try Imaging.load(short,maxPixel:400),"\(name) at \(share)"){error in
                    if type != .tiff {XCTAssertTrue(error.localizedDescription.contains("incomplete") && error.localizedDescription.contains(short.lastPathComponent),error.localizedDescription)}
                }
            }
        }
    }
    func testAWholePhotographIsNotMistakenForADamagedOne() throws {
        // Bytes after the end of a JPEG, as some cameras and phones add, are no fault.
        let jpeg=try write(.jpeg,"b.jpg");var padded=try Data(contentsOf:jpeg);padded.append(Data(repeating:0,count:4096));padded.append(Data("trailer".utf8))
        let trailing=folder.appendingPathComponent("trailing.jpg");try padded.write(to:trailing)
        XCTAssertNil(Imaging.incomplete(trailing));XCTAssertNoThrow(try Imaging.load(trailing,maxPixel:400))
        // A JPEG holding a small JPEG inside it, as photographs do for their own thumbnail, is whole only when the outer one ends.
        let small=try Data(contentsOf:write(.jpeg,"small.jpg")),outer=try Data(contentsOf:jpeg)
        var nested=Data([0xFF,0xD8,0xFF,0xE1]);let length=UInt16(min(65535,small.count+2));nested.append(contentsOf:[UInt8(length>>8),UInt8(length&255)]);nested.append(small.prefix(Int(length)-2));nested.append(outer.dropFirst(2))
        let withThumbnail=folder.appendingPathComponent("nested.jpg");try nested.write(to:withThumbnail)
        XCTAssertNil(Imaging.incomplete(withThumbnail))
        try nested.prefix(nested.count/2).write(to:withThumbnail);Imaging.forgetCompleteness()
        XCTAssertNotNil(Imaging.incomplete(withThumbnail),"The end of the picture inside does not count as the end of the photograph")
        // Something that is not a picture, or is missing, is left to the ordinary error.
        let text=folder.appendingPathComponent("notes.jpg");try Data("not a picture at all".utf8).write(to:text)
        XCTAssertNil(Imaging.incomplete(text));XCTAssertNil(Imaging.incomplete(folder.appendingPathComponent("absent.jpg")))
        XCTAssertThrowsError(try Imaging.load(text,maxPixel:400))
    }
    func testAFileCompletedLaterIsReadAgain() throws {
        let whole=try write(.jpeg,"c.jpg"),data=try Data(contentsOf:whole),copy=folder.appendingPathComponent("copying.jpg")
        try data.prefix(data.count/3).write(to:copy);XCTAssertThrowsError(try Imaging.load(copy,maxPixel:400))
        try data.write(to:copy);XCTAssertNoThrow(try Imaging.load(copy,maxPixel:400),"The verdict on a file is not kept once the file has changed")
    }
    func testACutShortPhotographIsNotExported() throws {
        let short=try cut(try write(.jpeg,"d.jpg"),to:0.4)
        var options=ExportOptions();options.format = .png
        XCTAssertThrowsError(try Exporter.render(Page(path:short.path),options:options)){XCTAssertTrue($0.localizedDescription.contains("incomplete"),$0.localizedDescription)}
    }
    // The same fault on the way out: Quartz writes a PDF to a full disk without reporting anything.
    func noisyPage(_ n: Int) throws -> Page {
        let url=folder.appendingPathComponent("page\(n).png")
        if !FileManager.default.fileExists(atPath:url.path) {try Exporter.encode(picture(),as:.png,quality:1,dpi:nil).write(to:url)}
        var p=Page(path:url.path);var a=Adjustments();a.brightness=Double(n)*0.03;p.adjustments=a;return p
    }
    func testAPDFThatWasNotWrittenWholeIsReported() throws {
        let url=folder.appendingPathComponent("book.pdf"),writer=try PDFWriter(url:url)
        for n in 0..<4 {try writer.add(try noisyPage(n),options:ExportOptions())}
        XCTAssertNoThrow(try writer.close())
        let size=try Data(contentsOf:url).count
        XCTAssertNoThrow(try PDFWriter.verify(url,pages:4,atLeast:size/2,password:nil))
        XCTAssertThrowsError(try PDFWriter.verify(url,pages:5,atLeast:0,password:nil),"A page is missing")
        XCTAssertThrowsError(try PDFWriter.verify(url,pages:4,atLeast:size*2,password:nil),"Smaller than the pictures put into it"){XCTAssertTrue($0.localizedDescription.contains("not written completely"),$0.localizedDescription)}
        for share in [0.3,0.9] {
            let short=folder.appendingPathComponent("short.pdf");try Data(contentsOf:url).prefix(Int(Double(size)*share)).write(to:short)
            XCTAssertThrowsError(try PDFWriter.verify(short,pages:4,atLeast:0,password:nil),"Cut to \(share)")
        }
        XCTAssertThrowsError(try PDFWriter.verify(folder.appendingPathComponent("absent.pdf"),pages:1,atLeast:0,password:nil))
        // A protected PDF is checked with its password.
        let locked=folder.appendingPathComponent("locked.pdf"),secret=try PDFWriter(url:locked,password:"open sesame")
        try secret.add(try noisyPage(0),options:ExportOptions());XCTAssertNoThrow(try secret.close())
        // A writer nothing was added to has nothing to check.
        XCTAssertNoThrow(try PDFWriter(url:folder.appendingPathComponent("empty.pdf")).close())
    }
    func testAPDFWrittenToAFullDiskFails() throws {
        // A three-megabyte volume, too small for the book.
        let image=folder.appendingPathComponent("small.dmg"),mount=folder.appendingPathComponent("mnt")
        func hdiutil(_ arguments: [String]) -> Bool {
            let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/hdiutil");p.arguments=arguments;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice;p.standardInput=FileHandle.nullDevice
            return (try? p.run()) != nil && {p.waitUntilExit();return p.terminationStatus == 0}()
        }
        try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:true)
        guard hdiutil(["create","-quiet","-size","3m","-fs","HFS+","-volname","KSFull",image.path]),hdiutil(["attach","-quiet","-nobrowse","-mountpoint",mount.path,image.path]) else {throw XCTSkip("Could not make a small test volume")}
        defer {_=hdiutil(["detach","-quiet","-force",mount.path])}
        let url=mount.appendingPathComponent("book.pdf"),writer=try PDFWriter(url:url)
        for n in 0..<10 {try writer.add(try noisyPage(n),options:ExportOptions())}
        XCTAssertThrowsError(try writer.close()){XCTAssertTrue($0.localizedDescription.contains("not written completely"),$0.localizedDescription)}
    }
    // Removing a PDF's document information is checked by reading the file back, not by the remover's own word.
    func testWhatIsLeftOfAPDFsDocumentInformationIsReported() throws {
        let url=folder.appendingPathComponent("clean.pdf"),writer=try PDFWriter(url:url)
        try writer.add(try noisyPage(0),options:ExportOptions());try writer.close()
        XCTAssertEqual(writer.informationLeft,[]);XCTAssertEqual(PDFInfo.remaining(url,password:nil),[])
        // A PDF as Quartz leaves it says what made it and when.
        let raw=folder.appendingPathComponent("raw.pdf");var box=CGRect(x:0,y:0,width:200,height:200)
        let context=try XCTUnwrap(CGContext(raw as CFURL,mediaBox:&box,nil));context.beginPDFPage(nil);context.endPDFPage();context.closePDF()
        let left=PDFInfo.remaining(raw,password:nil);XCTAssertTrue(left.contains("Producer") && left.contains("CreationDate"),"\(left)")
        try PDFInfo.strip(raw);XCTAssertEqual(PDFInfo.remaining(raw,password:nil),[])
        // A protected PDF is read with its password.
        let locked=folder.appendingPathComponent("locked2.pdf"),secret=try PDFWriter(url:locked,password:"open sesame")
        try secret.add(try noisyPage(0),options:ExportOptions());try secret.close();XCTAssertEqual(secret.informationLeft,[])
    }
}

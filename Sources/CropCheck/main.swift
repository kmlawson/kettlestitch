import Foundation
import CropCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fixture(_ index:Int)->CGImage {
    let w=1600,h=1200
    let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray:0.16,alpha:1));c.fill(CGRect(x:0,y:0,width:w,height:h))
    let inset=CGFloat(index%20)
    c.setFillColor(CGColor(gray:0.9,alpha:1));c.beginPath();c.move(to:CGPoint(x:100+inset,y:100));c.addLine(to:CGPoint(x:1500,y:130));c.addLine(to:CGPoint(x:1450,y:1100));c.addLine(to:CGPoint(x:140,y:1080));c.closePath();c.fillPath()
    c.setStrokeColor(CGColor(gray:0.25,alpha:1));c.setLineWidth(2)
    for col in 0..<2 {for row in 0..<35 {let y=CGFloat(180+row*24);c.move(to:CGPoint(x:CGFloat(220+col*650),y:y));c.addLine(to:CGPoint(x:CGFloat(720+col*650),y:y));c.strokePath()}}
    return c.makeImage()!
}
let args=CommandLine.arguments
if args.count>3 && args[1]=="--collection" {
    do{try collectionCheck(folder:args[2],output:args[3],count:args.count>4 ? Int(args[4]):nil)}catch{print(error);exit(1)}
} else if args.count>4 && args[1]=="--claude-files" {
    // Writes what Send to Claude would upload for one project page, without contacting anyone.
    do{
        let project=try Project.read(URL(fileURLWithPath:args[2]))
        guard let index=Int(args[3]),project.pages.indices.contains(index-1) else{print("No such page");exit(1)}
        let page=project.pages[index-1],directory=URL(fileURLWithPath:args[4])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try ClaudeReview.prepare(page,in:directory)
        try ClaudeReview.prompt(quad:page.quad).write(to:directory.appendingPathComponent("prompt.txt"),atomically:true,encoding:.utf8)
        try ClaudeReview.schema.write(to:directory.appendingPathComponent("schema.json"),atomically:true,encoding:.utf8)
        print("Wrote \(ClaudeReview.photoName), \(ClaudeReview.overlayName), prompt.txt and schema.json for \(page.path)")
    }catch{print(error);exit(1)}
} else if args.count>3 && args[1]=="--split" {
    // Proposes a split for each of a project's first pages and writes small copies of the two halves to inspect.
    do{
        let project=try Project.read(URL(fileURLWithPath:args[2])),directory=URL(fileURLWithPath:args[3])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var options=ExportOptions();options.format = .jpeg;options.jpegQuality=0.7;options.maxDPI=60
        let start=Date(),pages=project.pages.prefix(args.count>4 ? Int(args[4]) ?? 12:12)
        for (i,original) in pages.enumerated() {
            var page=original
            let proposal=try SplitDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),quad:page.quad,rotation:page.rotation)
            page.split=proposal.split
            try Exporter.writeImages(page,in:directory,name:String(format:"%04d",i+1),options:options)
            print(String(format:"%04d %@ top=%.3f bottom=%.3f %@",i+1,URL(fileURLWithPath:page.path).lastPathComponent,proposal.split.top,proposal.split.bottom,proposal.confident ? "fold found":"centre fallback"))
        }
        print(String(format:"RESULT pages=%d seconds=%.2f",pages.count,Date().timeIntervalSince(start)))
    }catch{print(error);exit(1)}
} else if args.count>3 && args[1]=="--deskew" {
    // Measures the tilt of each of a project's first pages and writes small deskewed copies to inspect.
    do{
        let project=try Project.read(URL(fileURLWithPath:args[2])),directory=URL(fileURLWithPath:args[3])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var options=ExportOptions();options.format = .jpeg;options.jpegQuality=0.7;options.maxDPI=60
        let start=Date(),pages=project.pages.prefix(args.count>4 ? Int(args[4]) ?? 12:12)
        for (i,original) in pages.enumerated() {
            var page=original
            page.deskew=try SkewDetector.detect(Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600),page:page)
            try Exporter.writeImages(page,in:directory,name:String(format:"%04d",i+1),options:options)
            let source=try Imaging.load(URL(fileURLWithPath:page.path),maxPixel:1600)
            let measured=try Exporter.quads(for:page,options:ExportOptions()).map{SkewDetector.detect(try Imaging.corrected(source,quad:$0,rotation:page.rotation))}
            print(String(format:"%04d %@ %@",i+1,URL(fileURLWithPath:page.path).lastPathComponent,measured.map{$0.confident ? String(format:"%.2f°",$0.angle):"unclear"}.joined(separator:" / ")))
        }
        print(String(format:"RESULT pages=%d seconds=%.2f",pages.count,Date().timeIntervalSince(start)))
    }catch{print(error);exit(1)}
} else if args.count>1 && args[1]=="--benchmark" {
    let count=args.count>2 ? Int(args[2]) ?? 300:300
    let start=Date();var found=0;var errorSum=0.0
    for i in 0..<count {
        autoreleasepool {
            do{let image=fixture(i);let candidates=try Detector().detect(image)
                if let best=candidates.first {found+=1
                    let expected=Quad([Point(140.0/1600,120.0/1200),Point(1450.0/1600,100.0/1200),Point(1500.0/1600,1070.0/1200),Point(Double(100+i%20)/1600,1100.0/1200)])
                    errorSum += best.quad.distance(expected)
                    _=try Imaging.corrected(image,quad:best.quad)
                }
            }catch{print("ERROR \(i): \(error)")}
        }
        if (i+1)%25==0 {print("Processed \(i+1)/\(count)");fflush(stdout)}
    }
    print(String(format:"RESULT images=%d detected=%d seconds=%.2f mean_normalized_corner_error=%.5f",count,found,Date().timeIntervalSince(start),errorSum/Double(max(found,1))))
} else if args.count>2 && args[1]=="--fixture" {
    let url=URL(fileURLWithPath:args[2]);let d=CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(d,fixture(0),nil);CGImageDestinationFinalize(d)
} else if args.count>1 {
    for path in args.dropFirst() {do{let image=try Imaging.load(URL(fileURLWithPath:path),maxPixel:1600);let results=try Detector().detect(image);let data=try JSONEncoder().encode(results);print(path);print(String(decoding:data,as:UTF8.self))}catch{print(error)}}
} else {print("CropCheck --benchmark [300] | --fixture path.jpg | --collection folder output [count] | --claude-files project.pagecrop page-number output-folder | --split project.pagecrop output-folder [count] | --deskew project.pagecrop output-folder [count] | image paths")}

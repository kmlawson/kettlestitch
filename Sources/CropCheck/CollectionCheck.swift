import Foundation
import CropCore
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

func writeJPEG(_ image:CGImage,_ url:URL)throws {
    guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil) else{throw CropError.message("Cannot create JPEG")}
    CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.88] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else{throw CropError.message("Cannot write JPEG")}
}
func collectionCheck(folder:String,output:String,count:Int?)throws {
    let destination=URL(fileURLWithPath:output);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
    let extensions=Set(["jpg","jpeg","heic","heif","png","tif","tiff","bmp"])
    let urls=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{extensions.contains($0.pathExtension.lowercased())}.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
    guard !urls.isEmpty else{throw CropError.message("No photographs")}
    let total=count ?? urls.count
    var project=Project(),found=0,failures=0,seconds:[Double]=[]
    var sheet:CGContext?
    let started=Date()
    for i in 0..<total {
        autoreleasepool {
            let url=urls[i%urls.count],start=Date();var page=Page(path:url.path)
            do {
                let image=try Imaging.load(url,maxPixel:1600)
                let results=try Detector().detect(image);page.candidates=results
                if let best=results.first{page.quad=best.quad;page.status="Check proposal";found+=1}else{page.status="No boundary — crop manually"}
                // Contact sheets show complete photographs with the proposed crop, never just cropped results.
                if i<urls.count {
                    if i%16==0{sheet=CGContext(data:nil,width:2400,height:1840,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue);sheet?.setFillColor(CGColor(gray:0.1,alpha:1));sheet?.fill(CGRect(x:0,y:0,width:2400,height:1840))}
                    if let c=sheet {
                        let x=CGFloat(i%4)*600,y=CGFloat(3-(i%16)/4)*460
                        let scale=min(580.0/CGFloat(image.width),420.0/CGFloat(image.height)),w=CGFloat(image.width)*scale,h=CGFloat(image.height)*scale
                        let r=CGRect(x:x+(600-w)/2,y:y+30+(420-h)/2,width:w,height:h)
                        c.draw(image,in:r);c.setStrokeColor(CGColor(red:0,green:1,blue:0.6,alpha:1));c.setLineWidth(2)
                        for (j,p) in page.quad.points.enumerated(){let v=CGPoint(x:r.minX+p.x*r.width,y:r.minY+(1-p.y)*r.height);if j==0{c.move(to:v)}else{c.addLine(to:v)}};c.closePath();c.strokePath()
                        let label="\(i+1)  \(url.lastPathComponent)  \(results.first?.source ?? "NO RESULT")"
                        let text=NSAttributedString(string:label,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,17,nil),NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:1,alpha:1)])
                        c.textPosition=CGPoint(x:x+14,y:y+9);CTLineDraw(CTLineCreateWithAttributedString(text),c)
                        if i%16==15 || i==urls.count-1 {try writeJPEG(c.makeImage()!,destination.appendingPathComponent(String(format:"contact-%02d.jpg",i/16+1)));sheet=nil}
                    }
                    project.pages.append(page)
                }
            }catch{failures+=1;page.status="Error: \(error.localizedDescription)";if i<urls.count{project.pages.append(page)};print("ERROR \(url.lastPathComponent) \(error)")}
            seconds.append(Date().timeIntervalSince(start))
        }
        if (i+1)%20==0{print("Processed \(i+1)/\(total)");fflush(stdout)}
    }
    try project.save(destination.appendingPathComponent("1940.3.kettlestitch"))
    seconds.sort()
    let result=String(format:"REAL_COLLECTION unique=%d processed=%d proposed=%d failures=%d total_seconds=%.2f median_seconds=%.3f p95_seconds=%.3f",urls.count,total,found,failures,Date().timeIntervalSince(started),seconds[seconds.count/2],seconds[min(seconds.count-1,Int(Double(seconds.count)*0.95))])
    print(result);try result.write(to:destination.appendingPathComponent("results.txt"),atomically:true,encoding:.utf8)
}

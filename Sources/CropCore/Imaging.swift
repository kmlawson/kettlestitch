import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers

public enum Imaging {
    public static let context = CIContext(options: [.cacheIntermediates: false])
    /// Upright pixel dimensions, read from the header only.
    public static func pixelSize(_ url: URL) -> CGSize? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue>0,height.doubleValue>0 else{return nil}
        let orientation=(properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width:height.doubleValue,height:width.doubleValue):CGSize(width:width.doubleValue,height:height.doubleValue)
    }
    public static func aspectRatio(_ url: URL) -> Double? {pixelSize(url).map{Double($0.width/$0.height)}}
    public static func load(_ url: URL, maxPixel: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {throw CropError.message("Cannot read image: \(url.lastPathComponent)")}
        return image
    }
    /// Divides out a blurred estimate of the paper, evening shadows and whitening the background.
    static func flattened(_ image: CIImage) -> CIImage {
        let extent=image.extent,scale=min(1,256/max(extent.width,extent.height))
        let small=image.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:scale,kCIInputAspectRatioKey:1.0]).clampedToExtent()
        // The maximum removes print narrower than the radius, leaving the paper tone.
        let paper=small.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:6.0])
            .applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:8.0])
            .transformed(by:CGAffineTransform(scaleX:1/scale,y:1/scale))
        return paper.applyingFilter("CIDivideBlendMode",parameters:[kCIInputBackgroundImageKey:image]).cropped(to:extent)
    }
    public static func process(_ input: CIImage, _ adjustments: Adjustments) -> CIImage {
        var image=input
        if adjustments.cleanup != .none {image=flattened(image)}
        let mono=adjustments.cleanup.isMonochrome
        if mono || adjustments.brightness != 0 || adjustments.contrast != 0 {
            image=image.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:adjustments.brightness*0.5,kCIInputContrastKey:exp2(adjustments.contrast),kCIInputSaturationKey:mono ? 0.0:1.0])
        }
        if let sharpness=adjustments.sharpness,sharpness>0 {
            // The radius follows the image size, so the preview and the full-resolution export look alike.
            let extent=image.extent
            image=image.clampedToExtent().applyingFilter("CIUnsharpMask",parameters:[kCIInputRadiusKey:max(extent.width,extent.height)/1500,kCIInputIntensityKey:min(1,sharpness)*2]).cropped(to:extent)
        }
        if adjustments.cleanup == .blackAndWhite {image=image.applyingFilter("CIColorThreshold",parameters:["inputThreshold":0.5])}
        return image
    }
    /// Zones given on the photograph, as corners in the pixels of the image that `quad` renders to (top-left origin),
    /// keeping only those that cover part of it.
    static func zonePolygons(_ zones: [[Point]], quad: Quad, rotation: Int, deskew: Double, width: Int, height: Int) -> [[CGPoint]] {
        let w=Double(width),h=Double(height),a=deskew * .pi/180,c=cos(a),s=sin(a)
        return zones.compactMap{zone in
            let corners=zone.compactMap{p->CGPoint? in
                guard let (u,v)=SplitGeometry.position(of:p,quad:quad,rotation:rotation) else {return nil}
                // The same turn the deskew gives the picture: counterclockwise as seen, about the centre.
                let dx=u*w-w/2,dy=v*h-h/2
                return CGPoint(x:w/2+dx*c+dy*s,y:h/2-dx*s+dy*c)
            }
            guard corners.count == 4 else {return nil}
            let xs=corners.map{$0.x},ys=corners.map{$0.y}
            let overlapX=min(w,xs.max()!)-max(0,xs.min()!),overlapY=min(h,ys.max()!)-max(0,ys.min()!)
            return overlapX>=1 && overlapY>=1 ? corners:nil
        }
    }
    /// True when `quad`'s output contains part of a picture zone, so it cannot be a one-bit image.
    public static func hasPictures(_ zones: [[Point]], quad: Quad, rotation: Int) -> Bool {
        !zonePolygons(zones,quad:quad,rotation:rotation,deskew:0,width:1000,height:1000).isEmpty
    }
    private static func grayBytes(_ image: CIImage, area: CGRect) throws -> (pixels: [UInt8], width: Int, height: Int) {
        guard let rendered=context.createCGImage(image,from:area,format:.L8,colorSpace:CGColorSpace(name:CGColorSpace.genericGrayGamma2_2)),let data=rendered.dataProvider?.data,let source=CFDataGetBytePtr(data) else {throw CropError.message("Could not render crop")}
        let w=rendered.width,h=rendered.height
        var pixels=[UInt8](repeating:0,count:w*h)
        for y in 0..<h {pixels.withUnsafeMutableBufferPointer{$0.baseAddress!.advanced(by:y*w).update(from:source+y*rendered.bytesPerRow,count:w)}}
        return (pixels,w,h)
    }
    /// Grayscale and black-and-white cleanup produce an 8-bit gray image; everything else RGBA.
    /// `deskew` is the content's clockwise tilt in degrees, which is turned back. `zones` are picture zones as
    /// corners on the photograph; in black-and-white output they keep their tones.
    public static func corrected(_ image: CGImage, quad: Quad, rotation: Int = 0, adjustments: Adjustments = Adjustments(), scale: Double = 1, deskew: Double = 0, zones: [[Point]] = []) throws -> CGImage {
        guard quad.valid else {throw CropError.message("Invalid crop corners")}
        let input=CIImage(cgImage:image), w=Double(image.width), h=Double(image.height)
        func vector(_ p: Point) -> CIVector {CIVector(x:p.x*w, y:(1-p.y)*h)}
        let p=quad.points
        let output=input.applyingFilter("CIPerspectiveCorrection", parameters:["inputTopLeft":vector(p[0]),"inputTopRight":vector(p[1]),"inputBottomRight":vector(p[2]),"inputBottomLeft":vector(p[3])])
        let orientations: [Int32] = [1,6,3,8]
        var rotated=output.oriented(forExifOrientation:orientations[((rotation%4)+4)%4])
        if scale>0,scale<1 {rotated=rotated.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:scale,kCIInputAspectRatioKey:1.0])}
        let e=rotated.extent,area=CGRect(x:ceil(e.minX),y:ceil(e.minY),width:max(1,floor(e.maxX)-ceil(e.minX)),height:max(1,floor(e.maxY)-ceil(e.minY)))
        if deskew != 0 {
            // The page keeps its size; the thin wedges the turn exposes repeat the edge of the paper.
            let turn=CGAffineTransform(translationX:e.midX,y:e.midY).rotated(by:deskew * .pi/180).translatedBy(x:-e.midX,y:-e.midY)
            rotated=rotated.clampedToExtent().transformed(by:turn).cropped(to:e)
        }
        let processed=process(rotated,adjustments)
        let level=adjustments.despeckle ?? 0
        if adjustments.cleanup == .blackAndWhite,level>0 || !zones.isEmpty {
            var (pixels,pw,ph)=try grayBytes(processed,area:area)
            Despeckle.clean(&pixels,width:pw,height:ph,level:level)
            let pictures=zonePolygons(zones,quad:quad,rotation:rotation,deskew:deskew,width:pw,height:ph)
            if !pictures.isEmpty {
                // Inside a zone the page is shown as a photograph: no paper whitening, no threshold.
                var plain=adjustments;plain.cleanup = .none;plain.despeckle=nil
                let tones=process(rotated,plain).applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.0])
                let photo=try grayBytes(tones,area:area).pixels
                for corners in pictures {
                    let minX=max(0,Int(corners.map{$0.x}.min()!.rounded(.down))),maxX=min(pw-1,Int(corners.map{$0.x}.max()!.rounded(.up)))
                    let minY=max(0,Int(corners.map{$0.y}.min()!.rounded(.down))),maxY=min(ph-1,Int(corners.map{$0.y}.max()!.rounded(.up)))
                    guard minX<=maxX,minY<=maxY else {continue}
                    for y in minY...maxY {for x in minX...maxX {
                        let px=Double(x)+0.5,py=Double(y)+0.5
                        var positive=0,negative=0
                        for i in 0..<4 {
                            let a=corners[i],b=corners[(i+1)%4]
                            let cross=(b.x-a.x)*(py-a.y)-(b.y-a.y)*(px-a.x)
                            if cross>0 {positive+=1} else if cross<0 {negative+=1}
                        }
                        if positive == 0 || negative == 0 {pixels[y*pw+x]=photo[y*pw+x]}
                    }}
                }
            }
            guard let provider=CGDataProvider(data:Data(pixels) as CFData),
                  let result=CGImage(width:pw,height:ph,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:pw,space:CGColorSpace(name:CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw CropError.message("Could not render crop")}
            return result
        }
        let mono=adjustments.cleanup.isMonochrome
        let rendered=mono ? context.createCGImage(processed,from:area,format:.L8,colorSpace:CGColorSpace(name:CGColorSpace.genericGrayGamma2_2)):context.createCGImage(processed,from:area)
        guard let result=rendered else {throw CropError.message("Could not render crop")}
        return result
    }
    /// Packs an 8-bit gray image into one bit per pixel.
    public static func bilevel(_ image: CGImage) throws -> CGImage {
        let w=image.width,h=image.height,row=(w+7)/8
        guard image.bitsPerPixel==8,let data=image.dataProvider?.data,let source=CFDataGetBytePtr(data) else {throw CropError.message("Black-and-white output needs a gray image")}
        var bits=[UInt8](repeating:0,count:row*h)
        for y in 0..<h {
            let line=source+y*image.bytesPerRow
            for x in 0..<w where line[x]>=128 {bits[y*row+(x>>3)] |= UInt8(0x80)>>UInt8(x&7)}
        }
        guard let provider=CGDataProvider(data:Data(bits) as CFData),
              let result=CGImage(width:w,height:h,bitsPerComponent:1,bitsPerPixel:1,bytesPerRow:row,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {throw CropError.message("Could not build black-and-white image")}
        return result
    }
    public static func export(_ page: Page, to url: URL) throws {
        var options=ExportOptions();options.format = .jpeg;options.jpegQuality=0.96
        try Exporter.writeImage(page,to:url,options:options)
    }
}

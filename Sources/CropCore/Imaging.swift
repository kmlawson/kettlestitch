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
        // A file cut short opens all the same, with gray or black where the picture is missing; it is refused here.
        if let problem=incomplete(url) {throw CropError.message(problem)}
        // A photograph that was being read when the app last crashed is left alone until the user says to try it again.
        if isHeld(url.path) {throw CropError.message("“\(url.lastPathComponent)” has been set aside: KettleStitch closed unexpectedly while reading it. File ▸ Try Set-Aside Photographs Again reads it once more.")}
        noteReading(url.path,begun:true);defer {noteReading(url.path,begun:false)}
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
        // Exposure scales the light itself, as a longer or shorter exposure would, before the tones are shaped.
        if let exposure=adjustments.exposure,exposure != 0 {image=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:max(-1,min(1,exposure))*2])}
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
    /// The strokes as a mask the size of the photograph: white where the brush went, soft at its edges.
    static func smudgeMask(_ smudges: [Smudge], extent: CGRect) -> CIImage? {
        let longer=max(extent.width,extent.height),reduce=min(1,1024/longer)
        let mw=max(1,Int((extent.width*reduce).rounded())),mh=max(1,Int((extent.height*reduce).rounded()))
        guard let c=CGContext(data:nil,width:mw,height:mh,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else {return nil}
        c.setFillColor(gray:0,alpha:1);c.fill(CGRect(x:0,y:0,width:mw,height:mh))
        c.setStrokeColor(gray:1,alpha:1);c.setLineCap(.round);c.setLineJoin(.round)
        for smudge in smudges where !smudge.points.isEmpty {
            func place(_ p: Point) -> CGPoint {CGPoint(x:p.x*Double(mw),y:(1-p.y)*Double(mh))}
            c.setLineWidth(max(1,2*smudge.radius*Double(max(mw,mh))))
            let first=place(smudge.points[0])
            c.move(to:first)
            // A single click still leaves a dot.
            if smudge.points.count == 1 {c.addLine(to:CGPoint(x:first.x+0.01,y:first.y))}
            for p in smudge.points.dropFirst() {c.addLine(to:place(p))}
            c.strokePath()
        }
        guard let mask=c.makeImage() else {return nil}
        let radius=smudges.map{$0.radius}.min() ?? 0.01
        return CIImage(cgImage:mask).transformed(by:CGAffineTransform(scaleX:extent.width/CGFloat(mw),y:extent.height/CGFloat(mh)))
            .clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(1,radius*Double(longer)*0.25)]).cropped(to:extent)
    }
    /// How strong the gray grain laid over a smudge is when the stroke does not say, 0 (none) to 1.
    public static let smudgeGrain = 0.35
    /// How a picture zone on a Black & White page is rendered. A zone is always kept as a photograph, never
    /// whitened like the paper, since that washes a picture out. `.grayscale` keeps its gray tones and `.color` its
    /// colours, both with the page's exposure, brightness, contrast and sharpness; `.none` leaves it exactly as
    /// photographed. `.blackAndWhite` is not a choice. Set once from the app's settings; it is a single value for
    /// the whole app, read by every render.
    public static var pictureZoneMode = Cleanup.grayscale
    /// The photograph with its smudges blurred in. The blur follows the photograph's size, so the preview and the
    /// full-resolution export hide the same print equally.
    /// A stroke that cannot be drawn is an error, never a stroke left out: what it hides must not be exported bare.
    public static func smudged(_ image: CIImage, _ smudges: [Smudge]) throws -> CIImage {
        var result=image
        let extent=image.extent,longer=Double(max(extent.width,extent.height))
        // Strokes of one strength and one amount of grain are blurred together.
        struct Kind: Hashable {let strength: Double, grain: Double}
        func kind(_ smudge: Smudge) -> Kind {Kind(strength:smudge.strength,grain:smudge.grain ?? smudgeGrain)}
        for each in Set(smudges.map(kind)).sorted(by:{($0.strength,$0.grain)<($1.strength,$1.grain)}) {
            let strength=each.strength
            guard let mask=smudgeMask(smudges.filter{kind($0) == each},extent:extent) else {throw CropError.message("Could not render smudges")}
            var blurred=result.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:longer*(0.002+0.02*strength)]).cropped(to:extent)
            // A little gray grain over the blur, so the smudge reads as paper texture rather than a smooth patch
            // and what lay under it is harder still to recover. The grain's size follows the photograph's.
            if each.grain>0,let noise=CIFilter(name:"CIRandomGenerator")?.outputImage {
                // Noise drawn in towards middle gray leaves the smudge's own tone unchanged on average.
                let amount=each.grain,grain=max(1,longer/1600)
                let keep=CIVector(x:amount,y:0,z:0,w:0),offset=0.5-amount/2
                let gray=noise.applyingFilter("CIColorMatrix",parameters:["inputRVector":keep,"inputGVector":keep,"inputBVector":keep,"inputAVector":CIVector(x:0,y:0,z:0,w:0),"inputBiasVector":CIVector(x:offset,y:offset,z:offset,w:1)])
                    .transformed(by:CGAffineTransform(scaleX:grain,y:grain)).cropped(to:extent)
                blurred=gray.applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:blurred]).cropped(to:extent)
            }
            result=blurred.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:mask])
        }
        return result
    }
    /// The photograph with its clone strokes copied in and then its smudges blurred in.
    public static func retouched(_ image: CIImage, smudges: [Smudge], clones: [CloneStroke]) throws -> CIImage {
        var result=image
        let extent=image.extent
        for stroke in clones {
            guard let mask=smudgeMask([Smudge(points:stroke.points,radius:stroke.radius,strength:0)],extent:extent) else {throw CropError.message("Could not render cloned areas")}
            // The picture slid so that what lies `offset` away sits under the brush. Core Image counts upward, photographs downward.
            let source=result.clampedToExtent().transformed(by:CGAffineTransform(translationX:-stroke.offset.x*extent.width,y:stroke.offset.y*extent.height)).cropped(to:extent)
            result=source.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:mask])
        }
        return try smudged(result,smudges)
    }
    public static func retouched(_ image: CGImage, smudges: [Smudge], clones: [CloneStroke]) throws -> CGImage {
        guard !smudges.isEmpty || !clones.isEmpty else {return image}
        let input=CIImage(cgImage:image)
        guard let result=context.createCGImage(try retouched(input,smudges:smudges,clones:clones),from:input.extent) else {throw CropError.message("Could not render smudges")}
        return result
    }
    public static func smudged(_ image: CGImage, _ smudges: [Smudge]) throws -> CGImage {try retouched(image,smudges:smudges,clones:[])}
    public static func corrected(_ image: CGImage, quad: Quad, rotation: Int = 0, adjustments: Adjustments = Adjustments(), scale: Double = 1, deskew: Double = 0, zones: [[Point]] = [], smudges: [Smudge] = [], clones: [CloneStroke] = [], zoneMode: Cleanup? = nil) throws -> CGImage {
        guard quad.valid else {throw CropError.message("Invalid crop corners")}
        let input=try retouched(CIImage(cgImage:image),smudges:smudges,clones:clones), w=Double(image.width), h=Double(image.height)
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
                let chosen=zoneMode ?? pictureZoneMode,mode=chosen == .blackAndWhite ? Cleanup.grayscale:chosen
                var plain=adjustments;plain.cleanup = .none;plain.despeckle=nil
                let tones=mode == .none ? rotated:process(rotated,plain)
                if mode != .grayscale {
                    // A picture in colour needs a colour image: the black-and-white page with the zones laid over it.
                    guard let provider=CGDataProvider(data:Data(pixels) as CFData),
                          let page=CGImage(width:pw,height:ph,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:pw,space:CGColorSpace(name:CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),
                          let stencil=CGContext(data:nil,width:pw,height:ph,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else {throw CropError.message("Could not render picture zones")}
                    stencil.setFillColor(gray:0,alpha:1);stencil.fill(CGRect(x:0,y:0,width:pw,height:ph));stencil.setFillColor(gray:1,alpha:1)
                    for corners in pictures {
                        stencil.beginPath();stencil.move(to:CGPoint(x:corners[0].x,y:CGFloat(ph)-corners[0].y))
                        for corner in corners.dropFirst() {stencil.addLine(to:CGPoint(x:corner.x,y:CGFloat(ph)-corner.y))}
                        stencil.closePath();stencil.fillPath()
                    }
                    guard let mask=stencil.makeImage() else {throw CropError.message("Could not render picture zones")}
                    let picture=tones.transformed(by:CGAffineTransform(translationX:-area.minX,y:-area.minY))
                    let mixed=picture.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(cgImage:page),kCIInputMaskImageKey:CIImage(cgImage:mask)])
                    guard let result=context.createCGImage(mixed,from:CGRect(x:0,y:0,width:pw,height:ph)) else {throw CropError.message("Could not render picture zones")}
                    return result
                }
                let photo=try grayBytes(tones.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.0]),area:area).pixels
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

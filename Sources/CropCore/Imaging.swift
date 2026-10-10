import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers

public enum Imaging {
    public static let context = CIContext(options: [.cacheIntermediates: false])
    public static func aspectRatio(_ url: URL) -> Double? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue>0,height.doubleValue>0 else{return nil}
        let orientation=(properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? height.doubleValue/width.doubleValue:width.doubleValue/height.doubleValue
    }
    public static func load(_ url: URL, maxPixel: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {throw CropError.message("Cannot read image: \(url.lastPathComponent)")}
        return image
    }
    public static func corrected(_ image: CGImage, quad: Quad, rotation: Int = 0) throws -> CGImage {
        guard quad.valid else {throw CropError.message("Invalid crop corners")}
        let input=CIImage(cgImage:image), w=Double(image.width), h=Double(image.height)
        func vector(_ p: Point) -> CIVector {CIVector(x:p.x*w, y:(1-p.y)*h)}
        let p=quad.points
        let output=input.applyingFilter("CIPerspectiveCorrection", parameters:["inputTopLeft":vector(p[0]),"inputTopRight":vector(p[1]),"inputBottomRight":vector(p[2]),"inputBottomLeft":vector(p[3])])
        let orientations: [Int32] = [1,6,3,8]
        let rotated=output.oriented(forExifOrientation:orientations[((rotation%4)+4)%4])
        guard let result=context.createCGImage(rotated, from:rotated.extent) else {throw CropError.message("Could not render crop")}
        return result
    }
    public static func export(_ page: Page, to url: URL) throws {
        // Decode only one full-resolution source at a time; EXIF is normalized first.
        let input=try load(URL(fileURLWithPath:page.path), maxPixel:100000)
        let result=try corrected(input,quad:page.quad,rotation:page.rotation)
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString,1,nil) else {throw CropError.message("Cannot create export")}
        CGImageDestinationAddImage(destination,result,[kCGImageDestinationLossyCompressionQuality:0.96] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {throw CropError.message("Export failed")}
    }
}

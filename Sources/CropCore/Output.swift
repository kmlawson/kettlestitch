import Foundation
import CoreGraphics

/// PDF page placement in points (1/72 inch) and the resulting image resolution.
public struct OutputLayout: Equatable {
    public var pageSize: CGSize
    public var imageRect: CGRect
    public var dpi: Double
}
public enum OutputGeometry {
    /// Used when a page has no physical size.
    public static let assumedDPI = 300.0
    /// Estimated size of the corrected output: mean opposite side lengths, swapped for quarter turns.
    public static func pixelSize(quad: Quad, sourceWidth: Double, sourceHeight: Double, rotation: Int) -> CGSize {
        guard quad.points.count == 4 else {return .zero}
        let p=quad.points.map{CGPoint(x:$0.x*sourceWidth,y:$0.y*sourceHeight)}
        func length(_ a:Int,_ b:Int)->Double {hypot(p[a].x-p[b].x,p[a].y-p[b].y)}
        let w=(length(0,1)+length(3,2))/2,h=(length(1,2)+length(0,3))/2
        return ((rotation%2)+2)%2 == 1 ? CGSize(width:h,height:w):CGSize(width:w,height:h)
    }
    public static func layout(pixelWidth: Double, pixelHeight: Double, format: PageFormat?) -> OutputLayout {
        guard pixelWidth>0,pixelHeight>0 else {return OutputLayout(pageSize:.zero,imageRect:.zero,dpi:assumedDPI)}
        if let paper=format?.fitInto {
            // The sheet turns to match the image; the image is centred at the largest size that fits.
            let (short,long)=paper.centimetres,landscape=pixelWidth>pixelHeight
            let page=CGSize(width:(landscape ? long:short)/2.54*72,height:(landscape ? short:long)/2.54*72)
            let scale=min(page.width/pixelWidth,page.height/pixelHeight)
            let size=CGSize(width:pixelWidth*scale,height:pixelHeight*scale)
            return OutputLayout(pageSize:page,imageRect:CGRect(x:(page.width-size.width)/2,y:(page.height-size.height)/2,width:size.width,height:size.height),dpi:72/scale)
        }
        var dpi=assumedDPI
        if let width=format?.widthCM,width>0 {dpi=pixelWidth/(width/2.54)}
        let size=CGSize(width:pixelWidth/dpi*72,height:pixelHeight/dpi*72)
        return OutputLayout(pageSize:size,imageRect:CGRect(origin:.zero,size:size),dpi:dpi)
    }
}

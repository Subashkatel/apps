import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Shared renderer for the approved Frontier and Paper Notes icon family.
// Usage: swift MakeReadingIcon.swift frontier|paper-notes output.iconset
 guard CommandLine.arguments.count == 3, ["frontier", "paper-notes"].contains(CommandLine.arguments[1]) else {
    fatalError("Expected frontier|paper-notes and an output iconset path")
}
let name = CommandLine.arguments[1] + "-a"
let folder = URL(fileURLWithPath: CommandLine.arguments[2])
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: a)
}
func render(_ name: String, size: Int) -> CGImage {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let plate = CGPath(roundedRect: CGRect(x: 96,y: 96,width: 832,height: 832),cornerWidth: 188,cornerHeight: 188,transform: nil)
    c.saveGState();c.addPath(plate);c.clip()
    let front = name.hasPrefix("frontier")
    let top: UInt32 = front ? 0x4C6652 : 0xB96047
    let bottom: UInt32 = front ? 0x243D32 : 0x7B382A
    c.drawLinearGradient(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(bottom),color(top)] as CFArray,locations: [0,1])!,start: CGPoint(x: 512,y: 96),end:CGPoint(x:512,y:928),options:[])
    c.restoreGState()
    c.setLineCap(.round);c.setLineJoin(.round)
    if name == "frontier-a" {
        // An open threshold. The large silhouette remains legible at 16 pixels.
        let door=CGMutablePath();door.move(to:CGPoint(x:302,y:292));door.addLine(to:CGPoint(x:302,y:582))
        door.addCurve(to:CGPoint(x:722,y:582),control1:CGPoint(x:302,y:838),control2:CGPoint(x:722,y:838))
        door.addLine(to:CGPoint(x:722,y:292))
        c.addPath(door);c.setStrokeColor(color(0xF1E8CC));c.setLineWidth(65);c.strokePath()
        c.setFillColor(color(0xDDB66A));c.fillEllipse(in:CGRect(x:440,y:460,width:144,height:144))
        let landscape=CGMutablePath();landscape.move(to:CGPoint(x:351,y:337));landscape.addCurve(to:CGPoint(x:673,y:435),control1:CGPoint(x:465,y:425),control2:CGPoint(x:567,y:460))
        c.addPath(landscape);c.setStrokeColor(color(0x9DB79F));c.setLineWidth(38);c.strokePath()
    } else if name == "paper-notes-a" {
        c.saveGState();c.setShadow(offset:CGSize(width:0,height:-14),blur:24,color:color(0x321C13,0.22))
        let page=CGMutablePath();page.move(to:CGPoint(x:320,y:268));page.addLine(to:CGPoint(x:676,y:268));page.addQuadCurve(to:CGPoint(x:710,y:302),control:CGPoint(x:710,y:268));page.addLine(to:CGPoint(x:710,y:630));page.addLine(to:CGPoint(x:581,y:761));page.addLine(to:CGPoint(x:320,y:761));page.addQuadCurve(to:CGPoint(x:286,y:727),control:CGPoint(x:286,y:761));page.addLine(to:CGPoint(x:286,y:302));page.addQuadCurve(to:CGPoint(x:320,y:268),control:CGPoint(x:286,y:268));page.closeSubpath()
        c.addPath(page);c.setFillColor(color(0xF6EDD4));c.fillPath();c.restoreGState()
        let fold=CGMutablePath();fold.move(to:CGPoint(x:581,y:761));fold.addLine(to:CGPoint(x:581,y:654));fold.addQuadCurve(to:CGPoint(x:605,y:630),control:CGPoint(x:581,y:630));fold.addLine(to:CGPoint(x:710,y:630));fold.closeSubpath();c.addPath(fold);c.setFillColor(color(0xD3C4A4));c.fillPath()
        c.setStrokeColor(color(0xB96047));c.setLineWidth(20);c.move(to:CGPoint(x:368,y:360));c.addLine(to:CGPoint(x:368,y:649));c.strokePath()
        c.setFillColor(color(0xD8BA75));c.fill(CGRect(x:410,y:449,width:213,height:45))
        c.setStrokeColor(color(0x5D6653));c.setLineWidth(23)
        for (y,end) in [(570.0,621.0),(470.0,598.0),(377.0,558.0)] {c.move(to:CGPoint(x:421,y:y));c.addLine(to:CGPoint(x:end,y:y));c.strokePath()}
    }
    return c.makeImage()!
}
func write(_ image:CGImage,_ url:URL){let d=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(d,image,nil);precondition(CGImageDestinationFinalize(d))}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    write(render(name, size: size*scale), folder.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
}

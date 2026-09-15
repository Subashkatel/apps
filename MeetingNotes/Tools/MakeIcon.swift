import AppKit
let directory=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->NSColor{NSColor(srgbRed:r,green:g,blue:b,alpha:1)}
for size in [16,32,64,128,256,512,1024] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let transform=NSAffineTransform();transform.scale(by:CGFloat(size)/1024);transform.concat()
    let tile=NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:208,yRadius:208)
    NSGradient(starting:color(0.19,0.23,0.17),ending:color(0.11,0.14,0.10))!.draw(in:tile,angle:-90)
    color(0.76,0.82,0.65).setFill()
    for x:CGFloat in [231,621]{NSBezierPath(ovalIn:NSRect(x:x,y:626,width:174,height:174)).fill()}
    color(0.40,0.48,0.34).setFill()
    for x:CGFloat in [270,660]{NSBezierPath(ovalIn:NSRect(x:x,y:666,width:96,height:96)).fill()}
    let head=NSBezierPath(roundedRect:NSRect(x:252,y:235,width:520,height:508),xRadius:222,yRadius:222)
    NSGradient(starting:color(0.86,0.90,0.76),ending:color(0.70,0.78,0.59))!.draw(in:head,angle:-90)
    color(0.94,0.92,0.79).setFill();NSBezierPath(ovalIn:NSRect(x:385,y:318,width:254,height:164)).fill()
    color(0.15,0.20,0.13).setFill()
    for x:CGFloat in [386,594]{NSBezierPath(ovalIn:NSRect(x:x,y:500,width:44,height:50)).fill()}
    NSBezierPath(roundedRect:NSRect(x:476,y:423,width:72,height:47),xRadius:22,yRadius:22).fill()
    let smile=NSBezierPath();smile.move(to:NSPoint(x:512,y:428));smile.line(to:NSPoint(x:512,y:391));smile.curve(to:NSPoint(x:475,y:379),controlPoint1:NSPoint(x:504,y:374),controlPoint2:NSPoint(x:486,y:372));smile.move(to:NSPoint(x:512,y:391));smile.curve(to:NSPoint(x:549,y:379),controlPoint1:NSPoint(x:520,y:374),controlPoint2:NSPoint(x:538,y:372));smile.lineWidth=12;smile.lineCapStyle = .round;color(0.15,0.20,0.13).setStroke();smile.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data=bitmap.representation(using:.png,properties:[:])!
    if size<=512{try data.write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"))}
    if size>=32{try data.write(to:directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}

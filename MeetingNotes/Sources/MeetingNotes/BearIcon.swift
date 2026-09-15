import AppKit

enum BearIcon {
    static func image(level:CGFloat,active:Bool,chicken:Bool)->NSImage {
        let image=NSImage(size:NSSize(width:22,height:22),flipped:false){rect in
            let ink=NSColor.black;ink.setFill()
            func hole(_ rect:NSRect){NSColor.clear.setFill();NSGraphicsContext.current?.compositingOperation = .copy;NSBezierPath(ovalIn:rect).fill();NSGraphicsContext.current?.compositingOperation = .sourceOver;ink.setFill()}
            if chicken {
                // A compact front-facing hen: one calm silhouette, a swept
                // three-lobed comb, and a centered beak. All features stay
                // inside the 22-point canvas, including the open beak.
                let comb=NSBezierPath()
                comb.move(to:NSPoint(x:7.6,y:15.7))
                comb.curve(to:NSPoint(x:6.7,y:19.1),controlPoint1:NSPoint(x:6.3,y:16.6),controlPoint2:NSPoint(x:5.9,y:18.1))
                comb.curve(to:NSPoint(x:9.4,y:18.4),controlPoint1:NSPoint(x:7.5,y:20.1),controlPoint2:NSPoint(x:8.8,y:19.6))
                comb.curve(to:NSPoint(x:11.2,y:20.8),controlPoint1:NSPoint(x:9.3,y:20.2),controlPoint2:NSPoint(x:10.2,y:21.3))
                comb.curve(to:NSPoint(x:12.5,y:18.4),controlPoint1:NSPoint(x:12.3,y:20.5),controlPoint2:NSPoint(x:12.5,y:19.5))
                comb.curve(to:NSPoint(x:15.1,y:19.1),controlPoint1:NSPoint(x:13.3,y:20.0),controlPoint2:NSPoint(x:14.8,y:20.0))
                comb.curve(to:NSPoint(x:14.4,y:15.6),controlPoint1:NSPoint(x:16.0,y:18.1),controlPoint2:NSPoint(x:15.5,y:16.7))
                comb.close();comb.fill()
                NSBezierPath(ovalIn:NSRect(x:3.2,y:4.1,width:15.6,height:13.6)).fill()
                hole(NSRect(x:6.3,y:10.5,width:2.1,height:2.4))
                hole(NSRect(x:13.6,y:10.5,width:2.1,height:2.4))
                let opening=max(0,min(1,level))
                let beak=NSBezierPath()
                beak.move(to:NSPoint(x:11,y:9.5))
                beak.line(to:NSPoint(x:13.4,y:8.2))
                beak.line(to:NSPoint(x:11,y:6.9-opening*1.8))
                beak.line(to:NSPoint(x:8.6,y:8.2))
                beak.close()
                NSColor.clear.setFill();NSGraphicsContext.current?.compositingOperation = .copy
                beak.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver;ink.setFill()
            } else {
                NSBezierPath(ovalIn:NSRect(x:2,y:14,width:6,height:6)).fill()
                NSBezierPath(ovalIn:NSRect(x:14,y:14,width:6,height:6)).fill()
                NSBezierPath(roundedRect:NSRect(x:3,y:4,width:16,height:14),xRadius:7,yRadius:7).fill()
                hole(NSRect(x:7,y:12,width:2,height:2));hole(NSRect(x:13,y:12,width:2,height:2))
                hole(NSRect(x:9.5,y:9,width:3,height:2))
                hole(NSRect(x:9-level/2,y:6-level,width:4+level,height:1+level*2.5))
            }
            if active{NSBezierPath(roundedRect:NSRect(x:7,y:1,width:8,height:1.5),xRadius:0.75,yRadius:0.75).fill()}
            return true
        }
        image.isTemplate=true;return image
    }
}

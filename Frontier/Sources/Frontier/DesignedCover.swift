import AppKit
import CryptoKit
import SwiftUI

/// Full-size composition scaled as a unit, including in tiny Continue reading covers.
/// Identity drives layout and geometry independently of the palette; adding or sorting
/// materials never changes an existing cover. Original artwork bypasses this view.
struct DesignedCover: View {
    let item: LibraryMaterial
    let design: Int
    private var seed: [UInt8] { Array(SHA256.hash(data: Data(item.id.utf8))) }
    static func fittedFont(title: String, name: String, box: CGSize) -> NSFont {
        var size: CGFloat = 34
        while size > 2 {
            let font = NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
            let rect = (title as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            if rect.height <= box.height - 8 && rect.width <= box.width { return font }
            size -= 0.5
        }
        return NSFont(name: name, size: 2) ?? .systemFont(ofSize: 2)
    }
    private static let coverArt: [Int: NSImage] = Dictionary(uniqueKeysWithValues: (0..<9).compactMap { n in
        Bundle.main.url(forResource: "cover-art-\(n)", withExtension: "png", subdirectory: "covers")
            .flatMap(NSImage.init(contentsOf:)).map { (n, $0) }
    })
    var body: some View {
        Canvas { context, size in
            let h: CGFloat = item.kind == .book || item.kind == .course ? 360 : 240 * sqrt(2)
            context.scaleBy(x: size.width / 240, y: size.height / h)
            let backgrounds: [UInt32] = [0x3B5662,0xCBB560,0xA7523C,0x344A3C,0x66465A,0xDED9C7,0xDAB7B1,0x3E584D,0xDDE1C8]
            let foregrounds: [UInt32] = [0xF1E7CF,0x2E4337,0xEEDEC0,0xC8D7BA,0xEDD8B4,0x344B51,0x573D47,0xEBDABE,0x465441]
            let composition = CoverComposition(index: design), palette = composition.illustrations[0] % backgrounds.count
            let paper = LibraryTheme.color(backgrounds[palette]), ink = LibraryTheme.color(foregrounds[palette])
            context.fill(Path(CGRect(x: 0, y: 0, width: 240, height: h)), with: .color(paper))
            let titleBox = CGRect(x: 23, y: 53, width: 194, height: h - 208)
            let title = Concept.plain(item.title)
            context.draw(Text(title).font(Font(Self.fittedFont(title: title, name: "Georgia", box: titleBox.size))).foregroundColor(ink), in: titleBox)
            context.draw(Text(item.kind == .paper ? "PAPER" : item.kind.rawValue.uppercased())
                .font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundColor(ink), at: CGPoint(x: 23, y: 26), anchor: .topLeading)
            context.draw(Text(item.isCollection ? "COLLECTION" : item.format.uppercased())
                .font(.system(size: 8)).tracking(1.1).foregroundColor(ink), at: CGPoint(x: 23, y: h - 23), anchor: .bottomLeading)
            let count = composition.illustrations.count
            let area = CGRect(x: 23, y: h - 140, width: 194, height: 98)
            for (position, family) in composition.illustrations.enumerated() {
                let width = (area.width - CGFloat(count-1)*8)/CGFloat(count)
                let box = CGRect(x: area.minX + CGFloat(position)*(width+8), y: area.minY, width: width, height: area.height)
                if let image = Self.coverArt[family] {
                    // Original artwork proportions, even in small or combined compositions.
                    let ratio = image.size.width/image.size.height
                    let w = min(box.width, box.height*ratio), height = w/ratio
                    var resolved = context.resolve(Image(nsImage: image))
                    resolved.shading = .color(ink)
                    context.draw(resolved, in: CGRect(x: box.midX-w/2, y: box.midY-height/2, width: w, height: height))
                } else {
                    let placement = CoverArtworkPlacement(in: box, rotated: false)
                    var art = context; art.translateBy(x: placement.frame.minX, y: placement.frame.minY)
                    art.scaleBy(x: placement.scale, y: placement.scale)
                    drawMotif(&art, ink: ink, family: family)
                }
            }
        }
    }
    private func drawMotif(_ context: inout GraphicsContext, ink: Color, family: Int) {
        func n(_ index: Int) -> CGFloat { CGFloat(seed[index % seed.count]) / 255 }
        func stroke(_ path: Path, _ width: CGFloat = 1.2) { context.stroke(path, with: .color(ink.opacity(0.85)), lineWidth: width) }
        switch family {
        case 0: // A constellation whose points come from this material's identity.
            var path = Path()
            for i in 0..<10 {
                let p = CGPoint(x: 8 + n(i + 3) * 174, y: 6 + n(i + 13) * 71)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                context.fill(Path(ellipseIn: CGRect(x: p.x-2, y: p.y-2, width: 4, height: 4)), with: .color(ink))
            }
            stroke(path)
        case 1: // Staggered print blocks.
            for i in 0..<9 {
                let height = 16 + n(i + 3) * 57
                let rect = CGRect(x: CGFloat(i) * 20 + 7, y: (83-height)/2, width: 11, height: height)
                context.fill(Path(rect), with: .color(ink.opacity(0.3 + Double(n(i + 12)) * 0.65)))
            }
        case 2: // Orbital diagram.
            for i in 0..<5 {
                let w = 48 + n(i + 3) * 125, h = 24 + n(i + 8) * 52
                stroke(Path(ellipseIn: CGRect(x: (190-w)/2, y: (83-h)/2, width: w, height: h)))
            }
        case 3: // Contours.
            for i in 0..<7 {
                var path = Path(); let y = CGFloat(i) * 9 + 10
                path.move(to: CGPoint(x: 6, y: y))
                path.addCurve(to: CGPoint(x: 184, y: y), control1: CGPoint(x: 35+n(i+3)*50, y: 3), control2: CGPoint(x: 110+n(i+13)*40, y: 80))
                stroke(path)
            }
        case 4: // A cut-paper mosaic.
            for i in 0..<12 {
                let x = CGFloat(i % 6) * 30 + 7, y = CGFloat(i / 6) * 37 + 6
                var p = Path(); p.move(to: CGPoint(x: x, y: y+30)); p.addLine(to: CGPoint(x: x+26, y: y+30))
                p.addLine(to: CGPoint(x: x+n(i+3)*26, y: y)); p.closeSubpath()
                context.fill(p, with: .color(ink.opacity(0.25 + Double(n(i+15))*0.7)))
            }
        case 5: // Interlocking arches.
            for i in 0..<5 {
                let x = CGFloat(i)*34+8, top = 5+n(i+3)*26
                var p = Path(); p.move(to: CGPoint(x: x, y: 77)); p.addLine(to: CGPoint(x: x, y: top+17))
                p.addQuadCurve(to: CGPoint(x: x+32, y: top+17), control: CGPoint(x: x+16, y: top-12))
                p.addLine(to: CGPoint(x: x+32, y: 77)); stroke(p, 2+n(i+8)*3)
            }
        case 6: // Offset typesetter's discs.
            for i in 0..<7 {
                let r = 10+n(i+3)*22, x = 6+CGFloat(i)*24, y = 5+n(i+13)*30
                let p = Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r))
                if i % 2 == 0 { context.fill(p, with: .color(ink.opacity(0.8))) } else { stroke(p, 2) }
            }
        case 7: // An identity-specific lattice.
            for i in 0..<24 {
                let x = CGFloat(i%8)*22+9, y = CGFloat(i/8)*24+8
                let r = 3+n(i+3)*13
                if seed[i] % 2 == 0 { stroke(Path(CGRect(x:x,y:y,width:r,height:r))) }
                else { context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:r,height:r)),with:.color(ink.opacity(0.8))) }
            }
        case 8: // A sunburst, with an open centre.
            for i in 0..<24 {
                let angle = Double(i) * .pi / 12, inner: CGFloat = 12 + n(i+3)*5
                let p = CGPoint(x: 95 + cos(angle)*inner, y: 41 + sin(angle)*inner)
                var ray = Path(); ray.move(to: p)
                ray.addLine(to: CGPoint(x: 95 + cos(angle)*75, y: 41 + sin(angle)*36)); stroke(ray, 1.5)
            }
        case 9: // Terraced steps.
            for i in 0..<7 {
                let x = CGFloat(i)*24+10, height = CGFloat(i+1)*9
                context.fill(Path(CGRect(x: x, y: 77-height, width: 21, height: height)), with: .color(ink.opacity(0.4+Double(i)*0.08)))
            }
        case 10: // Branching tree.
            var tree = Path(); tree.move(to: CGPoint(x:95,y:78)); tree.addLine(to: CGPoint(x:95,y:46))
            for i in 0..<7 {
                let x = CGFloat(i)*27+14
                tree.move(to: CGPoint(x:95,y:63)); tree.addQuadCurve(to: CGPoint(x:x,y:8+n(i+3)*12), control: CGPoint(x:x,y:43))
            }
            stroke(tree, 2)
        case 11: // Interlaced ribbons.
            for i in 0..<4 {
                var ribbon = Path(); ribbon.move(to: CGPoint(x:6,y:13+CGFloat(i)*17))
                ribbon.addCurve(to: CGPoint(x:184,y:70-CGFloat(i)*17), control1:CGPoint(x:65,y:80),control2:CGPoint(x:115,y:3))
                stroke(ribbon, 7)
            }
        case 12: // A botanical rosette.
            for i in 0..<10 {
                var petal = context; petal.translateBy(x:95,y:41); petal.rotate(by:.degrees(Double(i)*36))
                petal.fill(Path(ellipseIn:CGRect(x:3,y:-6,width:33,height:12)),with:.color(ink.opacity(i%2 == 0 ? 0.8 : 0.4)))
            }
        case 13: // Nested diamonds.
            for i in 0..<6 {
                let x: CGFloat = 12+CGFloat(i)*11, y: CGFloat = 5+CGFloat(i)*5
                var diamond = Path(); diamond.move(to:CGPoint(x:95,y:y)); diamond.addLine(to:CGPoint(x:190-x,y:41))
                diamond.addLine(to:CGPoint(x:95,y:83-y)); diamond.addLine(to:CGPoint(x:x,y:41)); diamond.closeSubpath(); stroke(diamond)
            }
        case 14: // A landscape of three silhouettes.
            for i in 0..<3 {
                var hill = Path(); hill.move(to:CGPoint(x:5,y:78))
                hill.addCurve(to:CGPoint(x:185,y:78),control1:CGPoint(x:28+CGFloat(i)*35,y:CGFloat(i)*20-20),control2:CGPoint(x:93+CGFloat(i)*25,y:15))
                hill.closeSubpath(); context.fill(hill,with:.color(ink.opacity(0.25+Double(i)*0.22)))
            }
        case 15: // Spiral.
            var spiral = Path()
            for i in 0...300 {
                let angle = Double(i)*0.06, radius = Double(i)*0.12
                let point=CGPoint(x:95+cos(angle)*radius*2,y:41+sin(angle)*radius)
                if i==0 { spiral.move(to:point) } else { spiral.addLine(to:point) }
            }; stroke(spiral,1.5)
        case 16: // Honeycomb.
            for row in 0..<3 { for col in 0..<6 {
                let x=CGFloat(col)*28+18+(row%2 == 0 ? 0 : 14), y=CGFloat(row)*23+18
                var hex = Path()
                for v in 0..<6 {
                    let a=Double(v)*Double.pi/3, p=CGPoint(x:x+cos(a)*12,y:y+sin(a)*12)
                    if v==0 { hex.move(to:p) } else { hex.addLine(to:p) }
                }; hex.closeSubpath(); stroke(hex)
            } }
        case 17: // Four blocks cut by circles.
            for i in 0..<4 {
                let x=CGFloat(i)*43+9
                context.fill(Path(CGRect(x:x,y:10,width:36,height:62)),with:.color(ink.opacity(i%2 == 0 ? 0.25 : 0.7)))
                stroke(Path(ellipseIn:CGRect(x:x+3,y:25,width:30,height:30)),2)
            }
        case 18: // Circuit paths.
            for i in 0..<6 {
                var track=Path(); let y=CGFloat(i)*11+12
                track.move(to:CGPoint(x:7,y:y)); track.addLine(to:CGPoint(x:40+CGFloat(i)*12,y:y))
                track.addLine(to:CGPoint(x:80+CGFloat(i)*12,y:75-y)); track.addLine(to:CGPoint(x:184,y:75-y)); stroke(track,2)
            }
        case 19: // Crosshatched waves.
            for i in 0..<11 {
                var wave=Path(); wave.move(to:CGPoint(x:6,y:CGFloat(i)*7+5))
                wave.addQuadCurve(to:CGPoint(x:184,y:78-CGFloat(i)*7),control:CGPoint(x:95,y:CGFloat(i)*5)); stroke(wave)
            }
        case 20: // Hourglass.
            var glass=Path(); glass.move(to:CGPoint(x:40,y:7)); glass.addLine(to:CGPoint(x:150,y:7))
            glass.addQuadCurve(to:CGPoint(x:40,y:76),control:CGPoint(x:60,y:40)); glass.addLine(to:CGPoint(x:150,y:76))
            glass.addQuadCurve(to:CGPoint(x:40,y:7),control:CGPoint(x:130,y:40)); glass.closeSubpath()
            context.fill(glass,with:.color(ink.opacity(0.8)))
        case 21: // Pendulums.
            for i in 0..<7 {
                let x=CGFloat(i)*25+18, y=22+n(i+3)*45
                var line=Path(); line.move(to:CGPoint(x:x,y:5)); line.addLine(to:CGPoint(x:x,y:y)); stroke(line)
                context.fill(Path(ellipseIn:CGRect(x:x-6,y:y-6,width:12,height:12)),with:.color(ink))
            }
        case 22: // Folded fan.
            for i in 0..<8 {
                var fold=Path(); fold.move(to:CGPoint(x:95,y:77))
                fold.addLine(to:CGPoint(x:8+CGFloat(i)*22,y:8)); fold.addLine(to:CGPoint(x:30+CGFloat(i)*22,y:8)); fold.closeSubpath()
                context.fill(fold,with:.color(ink.opacity(i%2 == 0 ? 0.8 : 0.22)))
            }
        default: // Offset checker print.
            for row in 0..<4 { for col in 0..<9 where (row+col)%2==0 {
                context.fill(Path(CGRect(x:CGFloat(col)*20+5,y:CGFloat(row)*18+6,width:18,height:16)),with:.color(ink.opacity(0.85)))
            } }

        }
    }
}

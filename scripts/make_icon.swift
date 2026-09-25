import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Playporter app icon — an upward arrow (thin rounded bars) filled with a smooth
// conic blend of the four Google colours (Maps-style): blue apex, red left,
// yellow centre/bottom, green right. No hard seams.

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()

func cg(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r/255), CGFloat(g/255), CGFloat(b/255), CGFloat(a)])!
}
typealias RGB = (r: Double, g: Double, b: Double)
let BLUE: RGB = (66, 133, 244), RED: RGB = (234, 67, 53), YELLOW: RGB = (251, 188, 5), GREEN: RGB = (52, 168, 83)
func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.r+(b.r-a.r)*t, a.g+(b.g-a.g)*t, a.b+(b.b-a.b)*t) }

let W = CGFloat(size), cx = W/2
let apexY: CGFloat = 786, armY: CGFloat = 512, armDX: CGFloat = 208, stemBottomY: CGFloat = 250, barWidth: CGFloat = 116
let apex = CGPoint(x: cx, y: apexY)

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background squircle (white with a subtle grey gradient + hairline edge)
let inset: CGFloat = 100, side = W - inset*2
let squircle = CGPath(roundedRect: CGRect(x: inset, y: inset, width: side, height: side),
                      cornerWidth: side*0.2237, cornerHeight: side*0.2237, transform: nil)
ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: [cg(255,255,255), cg(241,243,244)] as CFArray, locations: [0,1])!,
                       start: CGPoint(x:0,y:W), end: CGPoint(x:0,y:0), options: [])
ctx.restoreGState()
ctx.addPath(squircle); ctx.setStrokeColor(cg(218,220,224)); ctx.setLineWidth(3); ctx.strokePath()

// Whole-arrow outline (one shape → no overlapping seams)
let sp = CGMutablePath()
sp.move(to: CGPoint(x: cx - armDX, y: armY)); sp.addLine(to: apex); sp.addLine(to: CGPoint(x: cx + armDX, y: armY))
sp.move(to: apex); sp.addLine(to: CGPoint(x: cx, y: stemBottomY))
let outline = sp.copy(strokingWithWidth: barWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

ctx.saveGState()
ctx.addPath(outline); ctx.clip()

// 1) Conic blend around the apex (fine wedges). Angles (CG, y-up):
//    left arm ≈ 233°, stem (down) = 270°, right arm ≈ 307°.
func colorAt(_ deg: Double) -> RGB {
    if deg <= 233 { return RED }
    if deg < 270 { return lerp(RED, YELLOW, (deg-233)/(270-233)) }
    if deg < 307 { return lerp(YELLOW, GREEN, (deg-270)/(307-270)) }
    return GREEN
}
func pt(_ deg: Double, _ r: CGFloat) -> CGPoint {
    let a = deg * .pi/180
    return CGPoint(x: apex.x + r*CGFloat(cos(a)), y: apex.y + r*CGFloat(sin(a)))
}
let R: CGFloat = 1500
ctx.setShouldAntialias(false)   // seamless wedges (no moiré)
var a = 150.0
let step = 0.5
while a < 390.0 {
    let p = CGMutablePath(); p.move(to: apex)
    p.addLine(to: pt(a - 0.4, R)); p.addLine(to: pt(a + step + 0.4, R)); p.closeSubpath()
    let c = colorAt(min(max(a + step/2, 150), 360))
    ctx.addPath(p); ctx.setFillColor(cg(c.r, c.g, c.b)); ctx.fillPath()
    a += step
}
ctx.setShouldAntialias(true)

// 2) Soft blue halo at the apex (Maps: blue on top), fading out smoothly.
let halo = CGGradient(colorsSpace: cs, colors: [cg(BLUE.r,BLUE.g,BLUE.b,1), cg(BLUE.r,BLUE.g,BLUE.b,0)] as CFArray, locations: [0,1])!
ctx.drawRadialGradient(halo, startCenter: apex, startRadius: 0, endCenter: apex, endRadius: 250, options: [])

ctx.restoreGState()

// Export
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "icon_master.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("✅ icon_master.png généré (\(size)×\(size))")

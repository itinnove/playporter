import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r/255), CGFloat(g/255), CGFloat(b/255), CGFloat(a)])!
}

let googleBlue   = rgb(66, 133, 244)
let googleRed    = rgb(234, 67, 53)
let googleYellow = rgb(251, 188, 5)
let googleGreen  = rgb(52, 168, 83)

let W = CGFloat(size)

// White squircle background with a very subtle grey gradient + hairline edge
let inset: CGFloat = 100
let side = W - inset * 2
let bgRect = CGRect(x: inset, y: inset, width: side, height: side)
let radius = side * 0.2237
let squircle = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs,
                        colors: [rgb(255, 255, 255), rgb(241, 243, 244)] as CFArray,
                        locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: W), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Hairline edge so the tile is visible on white surfaces
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(218, 220, 224))
ctx.setLineWidth(3)
ctx.strokePath()

// Upward arrow drawn as thin rounded bars (Google Ads / Analytics thickness):
// a vertical stem + two long slim arms forming the head.
let cx = W / 2
let apexY: CGFloat = 786      // tip
let armY: CGFloat = 512       // where the arms end (lower than the tip)
let armDX: CGFloat = 208      // how far the arms spread
let stemBottomY: CGFloat = 250
let barWidth: CGFloat = 116   // bar thickness

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

// Build a polygon with a per-corner rounding radius via tangent arcs.
func roundedPolygon(_ pts: [CGPoint], radii: [CGFloat]) -> CGPath {
    let path = CGMutablePath()
    let n = pts.count
    path.move(to: midpoint(pts[n - 1], pts[0]))
    for i in 0..<n {
        path.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radii[i])
    }
    path.closeSubpath()
    return path
}

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(barWidth)

// Yellow: stem + left arm (the "rest")
ctx.setStrokeColor(googleYellow)
ctx.move(to: CGPoint(x: cx, y: apexY))
ctx.addLine(to: CGPoint(x: cx, y: stemBottomY))
ctx.strokePath()
ctx.move(to: CGPoint(x: cx - armDX, y: armY))
ctx.addLine(to: CGPoint(x: cx, y: apexY))
ctx.strokePath()

// Green: right arm, aligned through the apex
ctx.setStrokeColor(googleGreen)
ctx.move(to: CGPoint(x: cx, y: apexY))
ctx.addLine(to: CGPoint(x: cx + armDX, y: armY))
ctx.strokePath()

// Blue: round dot at the left arm tip (Google Ads style)
ctx.setFillColor(googleBlue)
let dotR = barWidth / 2
ctx.addEllipse(in: CGRect(x: cx - armDX - dotR, y: armY - dotR, width: barWidth, height: barWidth))
ctx.fillPath()

// Export PNG
guard let image = ctx.makeImage() else { fatalError("no image") }
let outURL = URL(fileURLWithPath: "icon_master.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("✅ icon_master.png généré (\(size)×\(size))")

// Renders the SoooDreamy app icon (1024x1024 PNG) purely from code so no
// binary assets need to live in the repo. Runs on macOS (CI) via:
//   swift ios/scripts/GenerateIcon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: GenerateIcon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outURL = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// Dreamy night-sky gradient background.
let bg = CGGradient(colorsSpace: cs,
                    colors: [rgba(0.075, 0.02, 0.16), rgba(0.16, 0.05, 0.30), rgba(0.36, 0.10, 0.42)] as CFArray,
                    locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// Soft radial glow behind the heart.
let glow = CGGradient(colorsSpace: cs,
                      colors: [rgba(1.0, 0.36, 0.54, 0.55), rgba(1.0, 0.36, 0.54, 0.0)] as CFArray,
                      locations: [0.0, 1.0])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 520, options: [])

// Scatter of stars.
var seed: UInt64 = 0x5EED_50DE
func rnd() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
}
for _ in 0..<70 {
    let x = rnd() * 1024, y = rnd() * 1024
    let r = 1.2 + rnd() * 3.2
    let a = 0.25 + rnd() * 0.6
    ctx.setFillColor(rgba(1, 1, 1, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}
// A few sparkles (4-point stars).
for _ in 0..<6 {
    let x = 80 + rnd() * 864, y = 80 + rnd() * 864
    let r = 10 + rnd() * 22
    ctx.setFillColor(rgba(1, 1, 1, 0.8))
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: y + r))
    p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * 0.12, y: y + r * 0.12))
    p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + r * 0.12, y: y - r * 0.12))
    p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * 0.12, y: y - r * 0.12))
    p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - r * 0.12, y: y + r * 0.12))
    ctx.addPath(p)
    ctx.fillPath()
}

// Parametric heart: x = 16sin^3 t, y = 13cos t - 5cos 2t - 2cos 3t - cos 4t  (y-up, matches CG).
func heartPath(center: CGPoint, scale: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = 240
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let x = 16 * pow(sin(t), 3)
        let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        let pt = CGPoint(x: center.x + x * scale, y: center.y + y * scale)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// Main heart with soft drop glow.
let heart = heartPath(center: CGPoint(x: 512, y: 500), scale: 21)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 90, color: rgba(1.0, 0.30, 0.50, 0.85))
ctx.setFillColor(rgba(1.0, 0.36, 0.54))
ctx.addPath(heart)
ctx.fillPath()
ctx.restoreGState()

// Gradient fill inside the heart.
ctx.saveGState()
ctx.addPath(heart)
ctx.clip()
let heartGrad = CGGradient(colorsSpace: cs,
                           colors: [rgba(1.0, 0.55, 0.70), rgba(1.0, 0.30, 0.52), rgba(0.72, 0.28, 0.86)] as CFArray,
                           locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(heartGrad, start: CGPoint(x: 300, y: 860), end: CGPoint(x: 760, y: 160), options: [])
// Glossy highlight.
let gloss = CGGradient(colorsSpace: cs,
                       colors: [rgba(1, 1, 1, 0.42), rgba(1, 1, 1, 0.0)] as CFArray,
                       locations: [0.0, 1.0])!
ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: 400, y: 700), startRadius: 0,
                       endCenter: CGPoint(x: 400, y: 700), endRadius: 330, options: [])
ctx.restoreGState()

// Small companion heart, slightly rotated.
ctx.saveGState()
ctx.translateBy(x: 700, y: 726)
ctx.rotate(by: 0.30)
let small = heartPath(center: .zero, scale: 6.4)
ctx.setShadow(offset: .zero, blur: 34, color: rgba(1, 1, 1, 0.65))
ctx.setFillColor(rgba(1.0, 0.92, 0.96, 0.98))
ctx.addPath(small)
ctx.fillPath()
ctx.restoreGState()

let img = ctx.makeImage()!
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("cannot create png destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("png finalize failed\n".data(using: .utf8)!)
    exit(1)
}
print("icon written to \(outURL.path)")

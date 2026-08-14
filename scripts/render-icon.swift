import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let style = args.first ?? "sheet"
let size = Int(args.count > 1 ? args[1] : "1024") ?? 1024
let output = args.count > 2 ? args[2] : "/tmp/opencode/icon.png"

var S: CGFloat = 1
var B: CGFloat = 1
func px(_ v: CGFloat) -> CGFloat { v * S }
func pxb(_ v: CGFloat) -> CGFloat { v * S * B }
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let mint = color(0.18, 0.78, 0.65)
let green = color(0.16, 0.72, 0.36)
let orange = color(0.98, 0.48, 0.12)
let ink = color(0.16, 0.19, 0.26)

func gradient(for name: String) -> NSGradient {
    switch name {
    case "teal":
        return NSGradient(colors: [
            color(0.10, 0.75, 0.80),
            color(0.15, 0.45, 0.92),
            color(0.35, 0.20, 0.88)
        ])!
    default:
        return NSGradient(colors: [
            color(0.32, 0.42, 0.98),
            color(0.55, 0.28, 0.95),
            color(0.78, 0.18, 0.85)
        ])!
    }
}

func drawBackground(_ ctx: CGContext, style: String) {
    let squircle = NSBezierPath(
        roundedRect: CGRect(x: px(32), y: px(32), width: px(960), height: px(960)),
        xRadius: px(218), yRadius: px(218)
    )
    gradient(for: style).draw(in: squircle, angle: -90)
    color(1, 1, 1, 0.22).setStroke()
    squircle.lineWidth = pxb(4)
    squircle.stroke()

    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [color(1, 1, 1, 0.14), color(1, 1, 1, 0)])!.draw(
        in: NSBezierPath(rect: CGRect(x: px(32), y: px(600), width: px(960), height: px(392))),
        angle: -90
    )
    ctx.restoreGState()
}

func drawTile(frame: CGRect, selected: Bool, status: NSColor?, ctx: CGContext) {
    let shadow = NSBezierPath(roundedRect: CGRect(
        x: frame.minX + px(10), y: frame.minY - px(10),
        width: frame.width, height: frame.height
    ), xRadius: px(22), yRadius: px(22))
    color(0, 0, 0, 0.22).setFill()
    shadow.fill()

    let path = NSBezierPath(roundedRect: frame, xRadius: px(22), yRadius: px(22))
    color(0.97, 0.98, 1.0).setFill()
    path.fill()

    if selected {
        color(1, 1, 1).setStroke()
        path.lineWidth = pxb(10)
    }
    path.stroke()

    ctx.saveGState()
    path.addClip()

    color(0.90, 0.92, 0.95).setFill()
    NSBezierPath(rect: CGRect(
        x: frame.minX, y: frame.maxY - px(36),
        width: frame.width, height: px(36)
    )).fill()

    if let dot = status {
        dot.setFill()
        NSBezierPath(ovalIn: CGRect(
            x: frame.minX + px(17), y: frame.maxY - px(25),
            width: pxb(13), height: pxb(13)
        )).fill()
    }

    color(0.66, 0.70, 0.78).setFill()
    let lineWidth = frame.width - px(56)
    var y = frame.maxY - px(72)
    for i in 0..<3 {
        let w = lineWidth * (i == 2 ? 0.55 : (i == 1 ? 0.8 : 1.0))
        NSBezierPath(roundedRect: CGRect(
            x: frame.minX + px(28), y: y - pxb(11),
            width: w, height: pxb(11)
        ), xRadius: pxb(5.5), yRadius: pxb(5.5)).fill()
        y -= px(32)
    }

    let cx = frame.minX + px(32)
    let cy = frame.minY + px(42)
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: cx, y: cy + px(24)))
    chevron.line(to: CGPoint(x: cx + px(17), y: cy + px(11)))
    chevron.line(to: CGPoint(x: cx, y: cy - px(2)))
    chevron.lineWidth = pxb(7.5)
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    ink.setStroke()
    chevron.stroke()
    mint.setFill()
    NSBezierPath(roundedRect: CGRect(
        x: cx + px(30), y: cy - px(1), width: pxb(22), height: pxb(26)
    ), xRadius: pxb(4), yRadius: pxb(4)).fill()

    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext, style: String) {
    drawBackground(ctx, style: style)
    let tile = px(380)
    let gap = px(28)
    let o = px((1024 - 380 * 2 - 28) / 2)
    drawTile(frame: CGRect(x: o, y: o + tile + gap, width: tile, height: tile), selected: true, status: green, ctx: ctx)
    drawTile(frame: CGRect(x: o + tile + gap, y: o + tile + gap, width: tile, height: tile), selected: false, status: green, ctx: ctx)
    drawTile(frame: CGRect(x: o, y: o, width: tile, height: tile), selected: false, status: orange, ctx: ctx)
    drawTile(frame: CGRect(x: o + tile + gap, y: o, width: tile, height: tile), selected: false, status: nil, ctx: ctx)
}

if style == "sheet" {
    let canvas = NSSize(width: 1100, height: 600)
    let image = NSImage(size: canvas)
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    color(0.85, 0.85, 0.87).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()

    S = 500.0 / 1024
    B = 1
    let entries: [(String, String, CGFloat, CGFloat)] = [
        ("E1 · Blue-Purple", "default", 40, 60),
        ("E2 · Teal-Blue", "teal", 560, 60)
    ]
    for (label, name, x, y) in entries {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        drawIcon(ctx, style: name)
        ctx.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: color(0.15, 0.15, 0.18)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let w = str.size().width
        str.draw(at: CGPoint(x: x + (500 - w) / 2, y: y - 48))
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("wrote \(output)")
} else {
    S = CGFloat(size) / 1024
    B = min(3, max(1, 128 / CGFloat(size)))
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    drawIcon(NSGraphicsContext.current!.cgContext, style: style)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("wrote \(output)")
}

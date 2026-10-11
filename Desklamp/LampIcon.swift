import AppKit

/// Menu bar desk lamp: `lamp.desk` when off; `lamp.desk.fill` plus a beam cone and a lit pool that age when on.
/// Drawn in black with alpha only and marked template, so the system tints it for light/dark and highlight.
enum LampIcon {
    private static let size = NSSize(width: 25, height: 22) // symbol plus room for the beam on the right
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

    // Beam geometry (flipped, pt): from the shade mouth's lip down to the desk line.
    private static let mouthL = NSPoint(x: 10.6, y: 11.4), mouthR = NSPoint(x: 16.2, y: 8.0)
    private static let deskY: CGFloat = 20.6
    /// Flattened ellipse where the beam meets the desk.
    private static let poolRect = NSRect(x: 12.9, y: 19.5, width: 25.2 - 12.9, height: 1.7)
    /// Clear border knocked out of the beam around the lamp (shows at the bulb's lower arc).
    private static let ringGap: CGFloat = 0.75
    /// Horizontal bands the cone is cut into when flickering.
    private static let flickerBands: [(CGFloat, CGFloat)] = [(7.0, 12.6), (13.8, 15.8), (17.4, 18.6)]

    /// `nil` stage means off.
    static func image(for stage: LampStage?) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            if let stage {
                let symbol = symbol("lamp.desk.fill")
                drawBeam(stage, around: symbol, in: ctx)
                drawSymbol(symbol, in: ctx)
            } else {
                drawSymbol(symbol("lamp.desk"), in: ctx)
            }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig)
    }

    private static func drawSymbol(_ symbol: NSImage?, in ctx: CGContext) {
        guard let symbol else { return }
        let rect = NSRect(origin: .zero, size: symbol.size)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: rect)
        NSColor.black.setFill()
        rect.fill(using: .sourceAtop)
        ctx.endTransparencyLayer()
    }

    /// Cone (banded when flickering), solid pool on the desk, then a clear ring knocked out around the lamp.
    private static func drawBeam(_ stage: LampStage, around symbol: NSImage?, in ctx: CGContext) {
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        ctx.saveGState()
        if stage == .flicker {
            let clip = NSBezierPath()
            for (y0, y1) in flickerBands {
                clip.appendRect(NSRect(x: 0, y: y0, width: size.width, height: y1 - y0))
            }
            clip.addClip()
        }
        let cone = NSBezierPath()
        cone.move(to: NSPoint(x: mouthL.x + 0.9, y: mouthL.y + 0.7))
        cone.line(to: NSPoint(x: mouthR.x + 0.5, y: mouthR.y + 1.0))
        cone.line(to: NSPoint(x: 24.6, y: deskY))
        cone.line(to: NSPoint(x: 13.8, y: deskY))
        cone.close()
        NSColor.black.withAlphaComponent(stage == .fresh ? 0.45 : 0.25).setFill()
        cone.fill()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setBlendMode(.copy)
        NSColor.black.withAlphaComponent(stage == .fresh ? 0.80 : 0.50).setFill()
        NSBezierPath(ovalIn: poolRect).fill()
        ctx.restoreGState()

        if let symbol {
            // Dilate the symbol by ringGap and erase it from the beam.
            let rect = NSRect(origin: .zero, size: symbol.size)
            ctx.setBlendMode(.destinationOut)
            let steps = 16
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                for r in [ringGap * 0.5, ringGap] {
                    symbol.draw(in: rect.offsetBy(dx: cos(t) * r, dy: sin(t) * r), from: .zero,
                                operation: .destinationOut, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            ctx.setBlendMode(.normal)
        }

        ctx.endTransparencyLayer()
    }
}

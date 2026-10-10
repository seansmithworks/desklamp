import AppKit

/// Menu bar desk lamp: `lamp.desk` when off; `lamp.desk.fill` plus a beam cone that ages when on.
/// Drawn in black with alpha only and marked template, so the system tints it for light/dark and highlight.
enum LampIcon {
    private static let size = NSSize(width: 25, height: 22) // symbol plus room for the beam on the right
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

    // Beam geometry (flipped, pt): from the shade mouth's lip down to the desk line.
    private static let mouthL = NSPoint(x: 10.6, y: 11.4), mouthR = NSPoint(x: 16.2, y: 8.0)
    private static let deskY: CGFloat = 20.6
    /// Horizontal bands the beam is cut into when flickering.
    private static let flickerBands: [(CGFloat, CGFloat)] = [(7.0, 12.6), (13.8, 15.8), (17.4, 18.6)]

    /// `nil` stage means off.
    static func image(for stage: LampStage?) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawSymbol(stage == nil ? "lamp.desk" : "lamp.desk.fill")
            switch stage {
            case nil: break
            case .fresh: drawBeam(alpha: 0.45)
            case .dimmer: drawBeam(alpha: 0.25)
            case .flicker:
                ctx.saveGState()
                let clip = NSBezierPath()
                for (y0, y1) in flickerBands {
                    clip.appendRect(NSRect(x: 0, y: y0, width: size.width, height: y1 - y0))
                }
                clip.addClip()
                drawBeam(alpha: 0.25)
                ctx.restoreGState()
            }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSymbol(_ name: String) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = NSRect(origin: .zero, size: symbol.size)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        symbol.draw(in: rect)
        NSColor.black.setFill()
        rect.fill(using: .sourceAtop)
        ctx.endTransparencyLayer()
    }

    /// Trapezoid from the shade mouth's lip to the desk line.
    private static func drawBeam(alpha: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: mouthL.x + 0.9, y: mouthL.y + 0.7))
        path.line(to: NSPoint(x: mouthR.x + 0.5, y: mouthR.y + 1.0))
        path.line(to: NSPoint(x: 24.6, y: deskY))
        path.line(to: NSPoint(x: 13.8, y: deskY))
        path.close()
        NSColor.black.withAlphaComponent(alpha).setFill()
        path.fill()
    }
}

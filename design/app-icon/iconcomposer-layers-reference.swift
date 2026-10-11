import AppKit

// Usage: swift layers.swift <outdir>
// Builds <outdir>/<variant>.icon packages (icon.json + Assets/*.png) from appicon.swift's geometry.
// Icon Composer canvas = 1024pt full-bleed (mask applied by the renderer), so the mockup's
// 824px tile body is scaled up by 1024/824 about the centre. Background goes into icon.json `fill`.
let outDir = CommandLine.arguments[1]
let S: CGFloat = 1024
let body: CGFloat = 824
let bleed = S / body

let open = NSPoint(x: 13.4, y: 9.9)
let mouthL = NSPoint(x: 10.6, y: 11.4), mouthR = NSPoint(x: 16.2, y: 8.0)
let dir = CGFloat(48.0 * .pi / 180)
let deskY: CGFloat = 20.6

struct RGBA { let r, g, b, a: CGFloat }
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xff)/255, green: CGFloat((hex >> 8) & 0xff)/255, blue: CGFloat(hex & 0xff)/255, alpha: a)
}
func srgb(_ n: NSColor) -> String {
  let x = n.usingColorSpace(.sRGB)!
  return String(format: "srgb:%.5f,%.5f,%.5f,%.5f", x.redComponent, x.greenComponent, x.blueComponent, x.alphaComponent)
}
func pt(_ o: NSPoint, _ a: CGFloat, _ d: CGFloat) -> NSPoint { NSPoint(x: o.x + cos(a)*d, y: o.y + sin(a)*d) }

struct Variant {
  let name: String
  let tileTop: NSColor, tileBottom: NSColor
  let lamp: NSColor
  let beamNear: NSColor, beamFar: NSColor
  let pool: NSColor?
  let deskSurface: NSColor?
  let bulb: NSColor?
}

let v: [Variant] = [
  Variant(name: "1-night-desk", tileTop: c(0x3B4AB8), tileBottom: c(0x111641), lamp: .white,
          beamNear: c(0xFFD866, 0.95), beamFar: c(0xFFC93C, 0.55), pool: c(0xFFD15A, 0.85), deskSurface: nil, bulb: nil),
  Variant(name: "2-warm-paper", tileTop: c(0xFFFDF8), tileBottom: c(0xEDE5D4), lamp: c(0x2B2B2E),
          beamNear: c(0xF29A12, 0.95), beamFar: c(0xF5A93A, 0.58), pool: c(0xF0A030, 0.65), deskSurface: nil, bulb: nil),
  Variant(name: "3-mono", tileTop: c(0x6A6E76), tileBottom: c(0x2A2C31), lamp: .white,
          beamNear: c(0xFFFFFF, 0.40), beamFar: c(0xFFFFFF, 0.30), pool: nil, deskSurface: nil, bulb: nil),
  Variant(name: "4-glow", tileTop: c(0x2E3039), tileBottom: c(0x0E0E12), lamp: c(0xB9B4AC),
          beamNear: c(0xFFF3C4, 0.95), beamFar: c(0xFFC24D, 0.30), pool: c(0xFFC85A, 1.0), deskSurface: c(0x2E2A26), bulb: c(0xFFF8E0)),
]

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let k: CGFloat = 26
let ox = S/2 - 12.3*k, oy = S/2 - 10.8*k + 8
func P(_ p: NSPoint) -> CGPoint { CGPoint(x: ox + p.x*k, y: oy + p.y*k) }
let deskPx = oy + deskY*k

// Draw one transparent 1024 layer in mockup coordinates (y-down), mapped to full-bleed.
func layer(_ draw: (CGContext) -> Void) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let r2 = rep.retagging(with: .sRGB)!
  NSGraphicsContext.saveGraphicsState()
  let base = NSGraphicsContext(bitmapImageRep: r2)!
  let cg = base.cgContext
  cg.translateBy(x: 0, y: S); cg.scaleBy(x: 1, y: -1)
  cg.translateBy(x: S/2, y: S/2); cg.scaleBy(x: bleed, y: bleed); cg.translateBy(x: -S/2, y: -S/2)
  let g = NSGraphicsContext(cgContext: cg, flipped: true); NSGraphicsContext.current = g
  g.imageInterpolation = .high
  draw(cg)
  NSGraphicsContext.restoreGraphicsState()
  return r2
}

func png(_ rep: NSBitmapImageRep, _ path: String) {
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func lampLayer(_ vv: Variant) -> NSBitmapImageRep {
  layer { cg in
    let sym = NSImage(systemSymbolName: "lamp.desk.fill", accessibilityDescription: nil)!
      .withSymbolConfiguration(.init(pointSize: 16*k, weight: .regular))!
    let lr = NSRect(x: ox, y: oy - (sym.size.height - 22*k)/2, width: sym.size.width, height: sym.size.height)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let dil: CGFloat = 7
    sym.draw(in: lr)
    for i in 0..<16 { let a = CGFloat(i) * .pi / 8
      sym.draw(in: lr.offsetBy(dx: cos(a)*dil, dy: sin(a)*dil)) }
    vv.lamp.setFill(); lr.insetBy(dx: -20, dy: -20).fill(using: .sourceAtop)
    cg.endTransparencyLayer()
  }
}

func beamLayer(_ vv: Variant) -> NSBitmapImageRep {
  layer { cg in
    let l0 = NSPoint(x: mouthL.x + 0.9, y: mouthL.y + 0.7), r0 = NSPoint(x: mouthR.x + 0.5, y: mouthR.y + 1.0)
    let beam = CGMutablePath()
    beam.move(to: P(l0)); beam.addLine(to: P(r0))
    beam.addLine(to: P(NSPoint(x: 24.6, y: deskY))); beam.addLine(to: P(NSPoint(x: 13.8, y: deskY))); beam.closeSubpath()
    cg.addPath(beam); cg.clip()
    let bg = CGGradient(colorsSpace: space, colors: [vv.beamNear.cgColor, vv.beamFar.cgColor] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg, start: P(open), end: P(NSPoint(x: 19.2, y: deskY)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }
}

func poolLayer(_ pc: NSColor) -> NSBitmapImageRep {
  layer { cg in
    let center = P(NSPoint(x: 19.1, y: deskY))
    cg.translateBy(x: center.x, y: center.y); cg.scaleBy(x: 1, y: 0.22)
    let rg = CGGradient(colorsSpace: space, colors: [pc.cgColor, pc.withAlphaComponent(pc.alphaComponent*0.5).cgColor, pc.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.55, 1])!
    cg.drawRadialGradient(rg, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 6.4*k, options: [])
  }
}

func deskLayer(_ ds: NSColor) -> NSBitmapImageRep {
  layer { cg in
    let dg = CGGradient(colorsSpace: space, colors: [ds.cgColor, ds.withAlphaComponent(0.6).cgColor] as CFArray, locations: [0, 1])!
    // Extend past the mockup tile edge so the full-bleed mask is covered.
    cg.clip(to: CGRect(x: -200, y: deskPx - 4, width: S + 400, height: S))
    cg.drawLinearGradient(dg, start: CGPoint(x: 0, y: deskPx), end: CGPoint(x: 0, y: S - (S - body)/2), options: [.drawsAfterEndLocation])
  }
}

func bulbLayer(_ bc: NSColor) -> NSBitmapImageRep {
  layer { cg in
    let cc = P(pt(open, dir, 0.9)); let r: CGFloat = 1.5*k
    cg.setShadow(offset: .zero, blur: 60, color: c(0xFFD36B, 1).cgColor)
    cg.setFillColor(bc.cgColor); cg.fillEllipse(in: CGRect(x: cc.x-r, y: cc.y-r, width: 2*r, height: 2*r))
  }
}

// icon.json builders
func L(_ name: String, glass: Bool, opacity: Double = 1, blend: String = "normal") -> [String: Any] {
  ["image-name": "\(name).png", "name": name, "glass": glass, "hidden": false, "opacity": opacity,
   "blend-mode": blend, "fill": "automatic",
   "position": ["scale": 1, "translation-in-points": [0, 0]]]
}
func G(_ name: String, _ layers: [[String: Any]], shadow: String = "neutral", shadowOpacity: Double = 0.5,
       translucency: Bool, specular: Bool = true) -> [String: Any] {
  ["name": name, "layers": layers, "lighting": "individual", "specular": specular,
   "shadow": ["kind": shadow, "opacity": shadowOpacity],
   "translucency": ["enabled": translucency, "value": 0.5]]
}

for vv in v {
  let dirURL = "\(outDir)/\(vv.name).icon"
  try? FileManager.default.createDirectory(atPath: "\(dirURL)/Assets", withIntermediateDirectories: true)
  png(lampLayer(vv), "\(dirURL)/Assets/lamp.png")
  png(beamLayer(vv), "\(dirURL)/Assets/beam.png")
  if let p = vv.pool { png(poolLayer(p), "\(dirURL)/Assets/pool.png") }
  if let d = vv.deskSurface { png(deskLayer(d), "\(dirURL)/Assets/desk.png") }
  if let b = vv.bulb { png(bulbLayer(b), "\(dirURL)/Assets/bulb.png") }

  // groups[0] = top of stack. Lamp is the glass object; light sits beneath it, flat.
  var groups: [[String: Any]] = []
  var lamp = L("lamp", glass: true)
  if vv.name == "2-warm-paper" {
    // Charcoal lamp vanishes once the system darkens the tile; flip it light in dark/tinted.
    lamp.removeValue(forKey: "fill")
    lamp["fill-specializations"] = [
      ["value": "automatic"],
      ["appearance": "dark", "value": ["solid": srgb(c(0xF4EEE2))]],
      ["appearance": "tinted", "value": ["solid": srgb(c(0xF4EEE2))]],
    ]
  }
  var lampLayers = [lamp]
  if vv.bulb != nil { lampLayers.insert(L("bulb", glass: false), at: 0) }
  groups.append(G("Lamp", lampLayers, translucency: false))
  var light = [L("beam", glass: false)]
  if vv.pool != nil { light.append(L("pool", glass: false)) }
  groups.append(G("Light", light, shadow: "none", shadowOpacity: 0, translucency: false, specular: false))
  if vv.deskSurface != nil {
    groups.append(G("Desk", [L("desk", glass: false)], shadow: "none", shadowOpacity: 0, translucency: false, specular: false))
  }

  let orient: [String: Any] = ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]
  let json: [String: Any] = [
    "color-space-for-untagged-svg-colors": "display-p3",
    "fill": ["linear-gradient": [srgb(vv.tileTop), srgb(vv.tileBottom)], "orientation": orient],
    "groups": groups,
    "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
  ]
  let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
  try! data.write(to: URL(fileURLWithPath: "\(dirURL)/icon.json"))
  print("wrote \(dirURL)")
}

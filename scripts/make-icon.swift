import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(calibratedRed: 0.08, green: 0.39, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
    NSColor.white.setStroke()
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: 210, y: 512))
    eye.curve(to: NSPoint(x: 814, y: 512), controlPoint1: NSPoint(x: 365, y: 752), controlPoint2: NSPoint(x: 659, y: 752))
    eye.curve(to: NSPoint(x: 210, y: 512), controlPoint1: NSPoint(x: 659, y: 272), controlPoint2: NSPoint(x: 365, y: 272))
    eye.lineWidth = 44; eye.lineJoinStyle = .round; eye.stroke()
    let iris = NSBezierPath(ovalIn: NSRect(x: 407, y: 407, width: 210, height: 210))
    iris.lineWidth = 40; iris.stroke()
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 536, y: 545, width: 45, height: 45)).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
}

import CoreGraphics
import Foundation
import ImageIO

// Draws the app icon (arrow dropping into a tray) and writes the asset catalog files.
let args = CommandLine.arguments
guard args.count > 1 else { print("usage: make_icon <out.png>"); exit(1) }
let out = URL(fileURLWithPath: args[1])
let dir = out.deletingLastPathComponent()
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let px = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))

let s = CGFloat(px) / 180
ctx.translateBy(x: 0, y: CGFloat(px))
ctx.scaleBy(x: s, y: -s)
ctx.setLineWidth(12)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.move(to: CGPoint(x: 90, y: 40)); ctx.addLine(to: CGPoint(x: 90, y: 102)); ctx.strokePath()
ctx.move(to: CGPoint(x: 62, y: 76)); ctx.addLine(to: CGPoint(x: 90, y: 104)); ctx.addLine(to: CGPoint(x: 118, y: 76)); ctx.strokePath()

ctx.setStrokeColor(CGColor(red: 1, green: 0.30, blue: 0.43, alpha: 1))
ctx.move(to: CGPoint(x: 52, y: 124)); ctx.addLine(to: CGPoint(x: 52, y: 138))
ctx.addLine(to: CGPoint(x: 128, y: 138)); ctx.addLine(to: CGPoint(x: 128, y: 124)); ctx.strokePath()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }

let iconJSON = #"{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
try iconJSON.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let rootJSON = #"{"info":{"author":"xcode","version":1}}"#
try rootJSON.write(to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("icon written to \(out.path)")

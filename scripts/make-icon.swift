// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho
//
// Draws the app icon (a pair of stem-style earbuds on a warm gradient) and writes a
// 1024×1024 PNG. Run through scripts/make-icon.sh, which also builds the .icns.
//
//     swift scripts/make-icon.swift <output.png>

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: Background: macOS icon grid (824 pt rounded square, 100 pt margin), warm red-orange.

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
ctx.addPath(tilePath)
ctx.setFillColor(color(0xE8402A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
linear(ctx, [color(0xFF7A3D), color(0xF0482C), color(0xC8202A)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
// Soft highlight in the upper part of the tile.
radial(ctx, [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)], center: CGPoint(x: 400, y: 860), radius: 520)
ctx.restoreGState()

// MARK: Earbud: head (rounded body), silicone tip, and stem. Drawn for the left ear,
// mirrored for the right one. Origin is the center of the head.

func drawEarbud(at center: CGPoint, angle: CGFloat, mirrored: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    if mirrored { ctx.scaleBy(x: -1, y: 1) }

    let head = CGRect(x: -118, y: -92, width: 236, height: 196)
    let headPath = CGPath(ellipseIn: head, transform: nil)
    let stem = CGRect(x: -6, y: -392, width: 92, height: 352)
    let stemPath = CGPath(roundedRect: stem, cornerWidth: 46, cornerHeight: 46, transform: nil)
    // The tip points inward (toward the other earbud), peeking out behind the head.
    let tip = CGRect(x: 52, y: -4, width: 112, height: 118)
    let tipPath = CGPath(ellipseIn: tip, transform: nil)

    let body = CGMutablePath()
    body.addPath(headPath)
    body.addPath(stemPath)

    // Drop shadow for the whole bud.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: mirrored ? -14 : 14, height: -22), blur: 36, color: color(0x5A0A0A, 0.45))
    ctx.addPath(body)
    ctx.addPath(tipPath)
    ctx.setFillColor(color(0xEEF0F3))
    ctx.fillPath()
    ctx.restoreGState()

    // Silicone ear tip (behind the head), dark gray with a soft highlight.
    ctx.saveGState()
    ctx.addPath(tipPath)
    ctx.clip()
    radial(ctx, [color(0x6B7079), color(0x3A3E45), color(0x24272C)], center: CGPoint(x: 120, y: 80), radius: 110)
    ctx.restoreGState()

    // Glossy white body: stem first, then the head on top.
    ctx.saveGState()
    ctx.addPath(stemPath)
    ctx.clip()
    linear(ctx, [color(0xD5D9DF), color(0xFFFFFF), color(0xE3E6EA), color(0xB9BEC6)],
           from: CGPoint(x: stem.minX, y: 0), to: CGPoint(x: stem.maxX, y: 0))
    ctx.restoreGState()

    // Small metallic cap at the bottom of the stem (the microphone grille).
    let cap = CGRect(x: stem.minX, y: stem.minY, width: stem.width, height: 70)
    ctx.saveGState()
    ctx.addPath(stemPath)
    ctx.clip()
    ctx.clip(to: cap)
    linear(ctx, [color(0x8E949C), color(0xD9DCE0), color(0x7D838B)],
           from: CGPoint(x: stem.minX, y: 0), to: CGPoint(x: stem.maxX, y: 0))
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(headPath)
    ctx.clip()
    radial(ctx, [color(0xFFFFFF), color(0xF3F4F6), color(0xCDD2D8)], center: CGPoint(x: 10, y: 50), radius: 170)
    ctx.restoreGState()

    // Specular highlight on the head.
    ctx.saveGState()
    ctx.addPath(headPath)
    ctx.clip()
    radial(ctx, [color(0xFFFFFF, 0.9), color(0xFFFFFF, 0)], center: CGPoint(x: 30, y: 62), radius: 70)
    ctx.restoreGState()

    ctx.restoreGState()
}

drawEarbud(at: CGPoint(x: 322, y: 650), angle: -0.16, mirrored: false)
drawEarbud(at: CGPoint(x: 702, y: 650), angle: 0.16, mirrored: true)

// MARK: Write PNG

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")

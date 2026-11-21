// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import AppKit

/// Developer tool: `RedmiBuds --ui-snapshot <dir> [--appearance light|dark]` opens the menu bar
/// popover, expands and collapses "More settings", closes and reopens it, and saves a PNG of
/// the popover plus its size after each step. It renders the app's own window, so no
/// screen-recording permission is needed. The README screenshots come from this.
@MainActor
enum UISnapshot {
    static let toggleMoreSettings = Notification.Name("UISnapshot.toggleMoreSettings")

    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--ui-snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(_ item: StatusItemController, into dir: URL) {
        setvbuf(stdout, nil, _IONBF, 0)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--appearance"), i + 1 < args.count {
            let appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
            NSApp.appearance = appearance
            item.setAppearance(appearance)
        }
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Wait for the earbuds to connect so the full UI is on screen.
            try? await Task.sleep(for: .seconds(6))

            item.show()
            try? await Task.sleep(for: .seconds(1))
            capture(item, "1-opened", dir)

            NotificationCenter.default.post(name: toggleMoreSettings, object: nil)
            try? await Task.sleep(for: .seconds(1))
            capture(item, "2-expanded", dir)

            NotificationCenter.default.post(name: toggleMoreSettings, object: nil)
            try? await Task.sleep(for: .seconds(1))
            capture(item, "3-collapsed", dir)

            item.close()
            try? await Task.sleep(for: .seconds(1))
            item.show()
            try? await Task.sleep(for: .seconds(1))
            capture(item, "4-reopened", dir)

            print("ui-snapshot: done")
            exit(0)
        }
    }

    private static func capture(_ item: StatusItemController, _ name: String, _ dir: URL) {
        guard let window = item.popoverWindow, let view = window.contentView else {
            return print("\(name): popover not shown")
        }
        print("\(name): window \(Int(window.frame.width))×\(Int(window.frame.height)) top=\(Int(window.frame.maxY))")
        guard let content = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: content)

        // The popover's material is drawn by the window server, so the cached view has a
        // transparent background. Composite it onto the window color, with rounded corners.
        let size = NSSize(width: content.pixelsWide, height: content.pixelsHigh)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: content.pixelsWide,
                                         pixelsHigh: content.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: out) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        (view.effectiveAppearance).performAsCurrentDrawingAppearance {
            let scale = size.width / view.bounds.width
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 12 * scale, yRadius: 12 * scale).addClip()
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            content.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import AppKit
import BudsKit

/// Menu bar-only app (LSUIElement): no Dock icon, no main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = BudsController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(controller: controller)
        controller.start()
        if let dir = UISnapshot.outputDirectory, let statusItem {
            UISnapshot.run(statusItem, into: dir)
        }
    }

    static func runApp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

extension Optional where Wrapped == NoiseMode {
    var symbol: String {
        switch self {
        case .noiseCancelling: "person.wave.2.fill"
        case .transparency: "ear.badge.waveform"
        default: "earbuds"
        }
    }
}

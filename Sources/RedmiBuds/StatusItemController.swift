// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import AppKit
import BudsKit
import Observation
import SwiftUI

/// Owns the menu bar item and its popover.
///
/// We use NSStatusItem + NSPopover instead of SwiftUI's `MenuBarExtra(.window)`: that panel
/// grows with its content but never shrinks back (collapsing "More settings" left a blank
/// area under the menu bar), and it can't be opened from code. A popover hosting the SwiftUI
/// view with `.preferredContentSize` resizes both ways and can be shown programmatically.
@MainActor
final class StatusItemController: NSObject {
    let controller: BudsController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(controller: BudsController) {
        self.controller = controller
        super.init()

        let hosting = NSHostingController(rootView: MenuContent(controller: controller))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
        }
        updateButton()
    }

    var isShown: Bool { popover.isShown }
    var popoverWindow: NSWindow? { popover.contentViewController?.view.window }

    @objc func togglePopover(_ sender: Any?) {
        isShown ? close() : show()
    }

    func show() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Accessory apps must activate explicitly, or the popover won't take key focus.
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { popover.performClose(nil) }

    /// Forces light or dark; `nil` follows the system (used by the UI snapshot tool).
    func setAppearance(_ appearance: NSAppearance?) { popover.appearance = appearance }

    /// Mirrors the noise mode as the icon and the lower earbud battery as the title.
    private func updateButton() {
        withObservationTracking {
            guard let button = statusItem.button else { return }
            let ready = controller.connection == .ready
            let state = controller.state
            let symbol = ready ? state.noiseMode.symbol : "earbuds"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Redmi Buds")
            let low = [state.left, state.right].compactMap { $0?.level }.min()
            button.title = ready ? low.map { " \($0)%" } ?? "" : ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
    }
}

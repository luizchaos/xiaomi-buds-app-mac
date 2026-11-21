// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import BudsKit
import Foundation

// User-facing names for BudsKit types.
//
// Strings live in Resources/Localization/<language>.lproj/Localizable.strings and are
// looked up in the app bundle (Bundle.main). To add a language, copy en.lproj, translate
// the values and run scripts/check-localizations.sh; the build script picks up every
// .lproj folder automatically. SwiftUI views use the same keys directly, e.g. Text("noise.title").

extension NoiseMode {
    var label: String {
        switch self {
        case .noiseCancelling: String(localized: "noise.mode.noiseCancelling")
        case .transparency: String(localized: "noise.mode.transparency")
        case .off: String(localized: "noise.mode.off")
        }
    }
}

extension ANCLevel {
    var label: String {
        switch self {
        case .light: String(localized: "noise.ancLevel.light")
        case .balanced: String(localized: "noise.ancLevel.balanced")
        case .deep: String(localized: "noise.ancLevel.deep")
        }
    }
}

extension TransparencyLevel {
    var label: String {
        switch self {
        case .regular: String(localized: "noise.transparencyLevel.regular")
        case .voice: String(localized: "noise.transparencyLevel.voice")
        case .ambient: String(localized: "noise.transparencyLevel.ambient")
        }
    }
}

extension EqualizerPreset {
    var label: String {
        switch self {
        case .standard: String(localized: "settings.equalizer.standard")
        case .voice: String(localized: "settings.equalizer.voice")
        case .bass: String(localized: "settings.equalizer.bass")
        case .treble: String(localized: "settings.equalizer.treble")
        case .custom: String(localized: "settings.equalizer.custom")
        }
    }
}

extension BudsController.Connection {
    var label: String {
        switch self {
        case .searching: String(localized: "connection.searching")
        case .notPaired: String(localized: "connection.notPaired")
        case .disconnected: String(localized: "connection.disconnected")
        case .connecting: String(localized: "connection.connecting")
        case .authenticating: String(localized: "connection.authenticating")
        case .ready: String(localized: "connection.ready")
        case .failed: String(localized: "connection.failed")
        }
    }
}

extension BudsError {
    var localizedMessage: String {
        switch self {
        case .sdpQueryFailed(let code):
            String(format: String(localized: "error.sdpQueryFailed"), code)
        case .serviceNotFound:
            String(localized: "error.serviceNotFound")
        case .channelOpenFailed(let code):
            String(format: String(localized: "error.channelOpenFailed"), code)
        case .channelRejected:
            String(localized: "error.channelRejected")
        case .authenticationTimedOut:
            String(localized: "error.authenticationTimedOut")
        }
    }
}

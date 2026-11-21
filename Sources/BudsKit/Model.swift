// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation

public enum NoiseMode: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0x00
    case noiseCancelling = 0x01
    case transparency = 0x02

    public var id: UInt8 { rawValue }
}

public enum ANCLevel: UInt8, CaseIterable, Identifiable, Sendable {
    case light = 0x01
    case balanced = 0x00
    case deep = 0x02

    public var id: UInt8 { rawValue }
}

public enum TransparencyLevel: UInt8, CaseIterable, Identifiable, Sendable {
    case regular = 0x00
    case voice = 0x01
    case ambient = 0x02

    public var id: UInt8 { rawValue }
}

public enum EqualizerPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case standard = 0x00
    case voice = 0x01
    case bass = 0x05
    case treble = 0x06
    case custom = 0x0A

    public var id: UInt8 { rawValue }
}

public enum Earbud: UInt8, Sendable {
    case left = 0x01
    case right = 0x02
    case both = 0x03
}

public struct Battery: Equatable, Sendable {
    public var level: Int
    public var charging: Bool

    /// Byte layout: bit 7 = charging, bits 0-6 = percentage, 0xFF = unknown/absent.
    init?(byte: UInt8) {
        guard byte != 0xFF else { return nil }
        level = Int(byte & 0x7F)
        charging = byte & 0x80 != 0
    }

    public init(level: Int, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

/// How a model turns adaptive noise cancelling on.
public enum AdaptiveANCStyle: Sendable, Equatable {
    /// A separate on/off setting (config 0x25), independent of the strength (5 Pro, 6 Pro).
    case flag
    /// A fourth noise-cancelling strength, 0x03 (3 Pro, 4 Pro). These models ignore 0x25.
    case strengthLevel

    /// The strength value that means "adaptive" on `.strengthLevel` models.
    static let adaptiveStrength: UInt8 = 0x03

    /// Picks the style from the advertised name. Unknown models keep `.flag`, the behavior
    /// verified on the 5 Pro and 6 Pro.
    public init(deviceName: String?) {
        let name = deviceName?.lowercased() ?? ""
        let strengthModels = ["redmi buds 3 pro", "redmi buds 4 pro"]
        self = strengthModels.contains(where: name.contains) ? .strengthLevel : .flag
    }
}

/// Everything we know about the earbuds. `nil` means "not reported yet".
public struct BudsState: Equatable, Sendable {
    public var left: Battery?
    public var right: Battery?
    public var caseBattery: Battery?

    public var noiseMode: NoiseMode?
    public var ancLevel: ANCLevel?
    public var adaptiveANC: Bool?
    public var transparencyLevel: TransparencyLevel?

    public var equalizer: EqualizerPreset?
    public var earDetection: Bool?
    public var adaptiveSound: Bool?
    public var dualConnection: Bool?
    public var autoAnswer: Bool?

    /// From the wear-status event: is each earbud in the ear / in the case.
    public var leftInEar: Bool?
    public var rightInEar: Bool?

    public var firmware: String?

    public init() {}
}

/// Configuration ids used with GET_CONFIG / SET_CONFIG / NOTIFY_CONFIG.
enum ConfigID: UInt8 {
    case gestures = 0x02
    case autoAnswer = 0x03
    case dualConnection = 0x04
    case earDetection = 0x06
    case equalizer = 0x07
    case findEarbuds = 0x09
    case longPressCycle = 0x0A
    case effectStrength = 0x0B
    case wearStatus = 0x0C
    case adaptiveANC = 0x25
    case adaptiveSound = 0x29
    case equalizerCurve = 0x37
}

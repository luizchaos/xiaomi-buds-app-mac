// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation

/// Protocol state machine with no I/O: feed it frames from the earbuds, send what it returns.
///
/// Handshake (both sides authenticate each other):
/// 1. host → `AUTH_CHALLENGE` with 16 random bytes
/// 2. buds → response; host → `AUTH_CONFIRM`
/// 3. buds → their own `AUTH_CHALLENGE`; host answers with the SAFER+ response
/// 4. buds → `AUTH_CONFIRM`; host acknowledges and asks for device info, run info and config
public struct BudsSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case authenticating
        case ready
    }

    public private(set) var phase: Phase = .idle
    public private(set) var state = BudsState()
    public let adaptiveStyle: AdaptiveANCStyle
    private var sequence: UInt8 = 0

    /// Config ids requested after the handshake. `.strengthLevel` models report adaptive
    /// through the strength, and their (unused) 0x25 setting would overwrite it.
    private var initialConfig: [ConfigID] {
        [.effectStrength] + (adaptiveStyle == .flag ? [.adaptiveANC] : [])
            + [.earDetection, .dualConnection, .autoAnswer, .adaptiveSound, .equalizer]
    }

    public init(adaptiveStyle: AdaptiveANCStyle = .flag) {
        self.adaptiveStyle = adaptiveStyle
    }

    private mutating func request(_ opcode: Opcode, _ payload: [UInt8]) -> Frame {
        defer { sequence &+= 1 }
        return Frame(.hostRequest, opcode, sequence: sequence, payload: payload)
    }

    // MARK: - Outgoing

    public mutating func start() -> [Frame] {
        phase = .authenticating
        state = BudsState()
        return [request(.authChallenge, [0x01] + BudsAuth.randomChallenge())]
    }

    public mutating func refresh() -> [Frame] {
        let all: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        return [request(.getDeviceInfo, all), request(.getRunInfo, all)]
            + initialConfig.map { request(.getConfig, [0x00, $0.rawValue]) }
    }

    public mutating func setNoiseMode(_ mode: NoiseMode) -> [Frame] {
        state.noiseMode = mode
        return [request(.anc, [0x02, 0x04, mode.rawValue])]
    }

    public mutating func setANCLevel(_ level: ANCLevel) -> [Frame] {
        state.ancLevel = level
        var frames: [Frame] = []
        if adaptiveStyle == .flag, state.adaptiveANC != false {
            frames += setFlag(.adaptiveANC, false)
        }
        state.adaptiveANC = false
        return frames + [setANCStrength(level.rawValue)]
    }

    public mutating func setAdaptiveANC(_ on: Bool) -> [Frame] {
        switch adaptiveStyle {
        case .flag:
            state.adaptiveANC = on
            return setFlag(.adaptiveANC, on)
        case .strengthLevel:
            // Turning adaptive off means picking a fixed strength instead.
            guard on else { return setANCLevel(state.ancLevel ?? .balanced) }
            state.adaptiveANC = true
            return [setANCStrength(AdaptiveANCStyle.adaptiveStrength)]
        }
    }

    private mutating func setANCStrength(_ value: UInt8) -> Frame {
        request(.setConfig, [0x04, 0x00, ConfigID.effectStrength.rawValue, 0x01, value])
    }

    public mutating func setTransparencyLevel(_ level: TransparencyLevel) -> [Frame] {
        state.transparencyLevel = level
        return [request(.setConfig, [0x04, 0x00, ConfigID.effectStrength.rawValue, 0x02, level.rawValue])]
    }

    public mutating func setEqualizer(_ preset: EqualizerPreset) -> [Frame] {
        state.equalizer = preset
        return [request(.setConfig, [0x03, 0x00, ConfigID.equalizer.rawValue, preset.rawValue])]
    }

    public mutating func setEarDetection(_ on: Bool) -> [Frame] {
        state.earDetection = on
        // Note the inverted value: 0x00 means enabled.
        return [request(.anc, [0x02, 0x06, on ? 0x00 : 0x01])]
    }

    public mutating func setAdaptiveSound(_ on: Bool) -> [Frame] {
        state.adaptiveSound = on
        return setFlag(.adaptiveSound, on)
    }

    public mutating func setDualConnection(_ on: Bool) -> [Frame] {
        state.dualConnection = on
        return setFlag(.dualConnection, on)
    }

    public mutating func setAutoAnswer(_ on: Bool) -> [Frame] {
        state.autoAnswer = on
        return setFlag(.autoAnswer, on)
    }

    /// Makes the earbuds beep. Call `stopFind()` to silence them.
    public mutating func startFind(_ which: Earbud = .both) -> [Frame] {
        stopFind() + [request(.setConfig, [0x04, 0x00, ConfigID.findEarbuds.rawValue, 0x01, which.rawValue])]
    }

    public mutating func stopFind() -> [Frame] {
        [request(.setConfig, [0x04, 0x00, ConfigID.findEarbuds.rawValue, 0x00, Earbud.both.rawValue])]
    }

    /// Sends an arbitrary host request. For protocol exploration with new models (CLI `raw`).
    public mutating func raw(_ opcode: Opcode, _ payload: [UInt8]) -> [Frame] {
        [request(opcode, payload)]
    }

    private mutating func setFlag(_ id: ConfigID, _ on: Bool) -> [Frame] {
        [request(.setConfig, [0x03, 0x00, id.rawValue, on ? 0x01 : 0x00])]
    }

    // MARK: - Incoming

    /// Handles one frame and returns the frames to send back.
    public mutating func handle(_ frame: Frame) -> [Frame] {
        guard let opcode = frame.opcode else { return [] }
        let isResponse = frame.type == .response

        switch opcode {
        case .authChallenge where isResponse:
            // The earbuds answered our challenge. Like the vendor app, we don't verify it.
            return [request(.authConfirm, [0x01, 0x00])]

        case .authChallenge:
            guard frame.payload.count >= 17 else { return [] }
            let answer = BudsAuth.response(to: Array(frame.payload[1...16]))
            return [Frame(.response, .authChallenge, sequence: frame.sequence, payload: [0x01] + answer)]

        case .authConfirm where isResponse:
            return []

        case .authConfirm:
            phase = .ready
            return [Frame(.response, .authConfirm, sequence: frame.sequence, payload: [0x01])] + refresh()

        case .getDeviceInfo:
            decodeDeviceInfo(frame.payload)
            return []

        case .getRunInfo:
            decodeRunInfo(frame.payload)
            return []

        case .getConfig:
            decodeConfig(frame.payload)
            return []

        case .reportStatus:
            decodeStatus(frame.payload)
            return isResponse ? [] : [Frame(.response, .reportStatus, sequence: frame.sequence)]

        case .notifyConfig:
            decodeNotify(frame.payload)
            return isResponse ? [] : [Frame(.response, .notifyConfig, sequence: frame.sequence)]

        case .anc, .setConfig:
            return []
        }
    }

    // MARK: - Decoding

    /// Walks `[len][id][value × (len-1)]` records.
    private static func records(_ payload: [UInt8], _ body: (UInt8, ArraySlice<UInt8>) -> Void) {
        var i = 0
        while i + 1 < payload.count {
            let length = Int(payload[i])
            guard length > 0, i + length < payload.count else { break }
            body(payload[i + 1], payload[(i + 2)..<(i + 1 + length)])
            i += length + 1
        }
    }

    private mutating func setBatteries(_ v: ArraySlice<UInt8>) {
        let b = Array(v)
        guard b.count >= 3 else { return }
        state.left = Battery(byte: b[0])
        state.right = Battery(byte: b[1])
        state.caseBattery = Battery(byte: b[2])
    }

    private mutating func decodeDeviceInfo(_ payload: [UInt8]) {
        Self.records(payload) { id, value in
            let v = Array(value)
            switch id {
            case 0x01 where v.count >= 2:
                state.firmware = v.prefix(2).map { "\($0 >> 4).\($0 & 0x0F)" }.joined(separator: ".")
            case 0x07:
                setBatteries(value)
            default:
                break
            }
        }
    }

    private mutating func decodeRunInfo(_ payload: [UInt8]) {
        Self.records(payload) { id, value in
            guard let first = value.first else { return }
            switch id {
            case 0x09: state.noiseMode = NoiseMode(rawValue: first)
            case 0x0A: state.earDetection = first == 0x00
            default: break
            }
        }
    }

    private mutating func decodeStatus(_ payload: [UInt8]) {
        Self.records(payload) { id, value in
            switch id {
            case 0x00: setBatteries(value)
            case 0x04: if let m = value.first { state.noiseMode = NoiseMode(rawValue: m) }
            default: break
            }
        }
    }

    /// GET_CONFIG response: `[len?] 00 <config id> <values…>`.
    private mutating func decodeConfig(_ payload: [UInt8]) {
        guard payload.count >= 4, let id = ConfigID(rawValue: payload[2]) else { return }
        let v = Array(payload[3...])
        let flag = v[0] == 0x01
        switch id {
        case .effectStrength where v.count >= 2:
            if v[0] == 0x01 { decodeANCStrength(v[1]) }
            if v[0] == 0x02 { state.transparencyLevel = TransparencyLevel(rawValue: v[1]) }
        case .adaptiveANC where adaptiveStyle == .flag: state.adaptiveANC = flag
        case .adaptiveSound: state.adaptiveSound = flag
        case .dualConnection: state.dualConnection = flag
        case .autoAnswer: state.autoAnswer = flag
        case .equalizer: state.equalizer = EqualizerPreset(rawValue: v[0])
        default: break
        }
    }

    /// On `.strengthLevel` models 0x03 means adaptive. Elsewhere unknown values (the 6 Pro
    /// reports some outside the table) are left unmapped rather than guessed.
    private mutating func decodeANCStrength(_ value: UInt8) {
        if adaptiveStyle == .strengthLevel {
            state.adaptiveANC = value == AdaptiveANCStyle.adaptiveStrength
            if let level = ANCLevel(rawValue: value) { state.ancLevel = level }
        } else {
            state.ancLevel = ANCLevel(rawValue: value)
        }
    }

    /// NOTIFY_CONFIG: records shaped `[len] 00 <config id> <values…>`.
    private mutating func decodeNotify(_ payload: [UInt8]) {
        Self.records(payload) { _, value in
            let v = Array(value)
            guard v.count >= 2, let id = ConfigID(rawValue: v[0]) else { return }
            switch id {
            case .wearStatus:
                // Bits 3…0: left in ear, right in ear, left in case, right in case.
                state.leftInEar = v[1] & 0x08 != 0
                state.rightInEar = v[1] & 0x04 != 0
            case .effectStrength where v.count >= 3:
                let mode = NoiseMode(rawValue: v[1])
                state.noiseMode = mode
                if mode == .noiseCancelling { decodeANCStrength(v[2]) }
                if mode == .transparency { state.transparencyLevel = TransparencyLevel(rawValue: v[2]) }
            default:
                break
            }
        }
    }
}

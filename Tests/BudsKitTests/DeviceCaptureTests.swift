// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

@testable import BudsKit
import Testing

/// Frames captured from real earbuds (MAC addresses in run info replaced with zeros).
/// They pin down the per-model differences the session must keep handling.
@Suite struct DeviceCaptureTests {
    private func hex(_ s: String) -> [UInt8] {
        s.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func feed(_ session: inout BudsSession, _ stream: String) -> [Frame] {
        var parser = FrameParser()
        return parser.feed(hex(stream)).flatMap { session.handle($0) }
    }

    @Test func redmiBuds5Pro() {
        var s = BudsSession()
        _ = feed(&s, """
        FE DC BA 04 02 00 38 00 02 11 00 52 65 64 6D 69 20 42 75 64 73 20 35 20 50 72 6F 05 01 43 77 43 77 02 02 5F 05 03 27 17 50 6D 02 04 01 02 05 00 03 06 43 77 02 08 01 04 07 5F 5F FF 02 0D 01 EF \
        FE DC BA 04 09 00 28 00 03 07 00 00 00 00 00 00 00 07 01 00 00 00 00 00 00 03 02 04 00 02 03 01 02 04 00 02 06 00 02 09 02 02 0A 00 02 0B 00 EF \
        FE DC BA 04 F3 00 07 00 04 04 00 0B 02 01 EF
        """)
        #expect(s.state.firmware == "4.3.7.7")
        #expect(s.state.left == Battery(level: 95, charging: false))
        #expect(s.state.right == Battery(level: 95, charging: false))
        #expect(s.state.caseBattery == nil)
        #expect(s.state.noiseMode == .transparency)
        #expect(s.state.transparencyLevel == .voice)
        #expect(s.state.earDetection == true)

        // The 5 Pro sends events with type C7; they must be decoded and acknowledged.
        let acks = feed(&s, "FE DC BA C7 F4 00 05 02 03 00 0C 0C EF FE DC BA C7 F4 00 06 04 04 00 0B 01 01 EF")
        #expect(s.state.leftInEar == true && s.state.rightInEar == true)
        #expect(s.state.noiseMode == .noiseCancelling)
        #expect(s.state.ancLevel == .light)
        #expect(acks == [Frame(.response, .notifyConfig, sequence: 2), Frame(.response, .notifyConfig, sequence: 4)])
    }

    @Test func redmiBuds6Pro() {
        var s = BudsSession()
        _ = feed(&s, """
        FE DC BA 04 02 00 3E 00 02 11 00 52 65 64 6D 69 20 42 75 64 73 20 36 20 50 72 6F 05 01 13 73 13 73 02 02 5A 05 03 27 17 50 9E 02 04 01 02 05 00 03 06 13 73 02 08 01 04 07 5A 50 FF 02 0D 01 02 0E 03 02 0F 01 EF \
        FE DC BA 04 F3 00 06 00 05 03 00 25 01 EF
        """)
        #expect(s.state.firmware == "1.3.7.3")
        #expect(s.state.left == Battery(level: 90, charging: false))
        #expect(s.state.right == Battery(level: 80, charging: false))
        #expect(s.state.adaptiveANC == true)

        // The 6 Pro sends events with type 87 (no status byte), including ANC strengths
        // outside the 5 Pro table, which must be ignored rather than misread.
        let acks = feed(&s, "FE DC BA 87 0E 00 04 03 02 04 01 EF FE DC BA 87 F4 00 06 04 04 00 0B 01 0B EF")
        #expect(s.state.noiseMode == .noiseCancelling)
        #expect(s.state.ancLevel == nil)
        #expect(acks == [Frame(.response, .reportStatus, sequence: 3), Frame(.response, .notifyConfig, sequence: 4)])
    }

    @Test func redmiBuds4Pro() {
        var s = BudsSession(adaptiveStyle: AdaptiveANCStyle(deviceName: "Redmi Buds 4 Pro"))
        #expect(s.adaptiveStyle == .strengthLevel)
        _ = feed(&s, """
        FE DC BA 04 02 00 3B 00 02 11 00 52 65 64 6D 69 20 42 75 64 73 20 34 20 50 72 6F 05 01 20 22 20 22 02 02 64 05 03 5A 4D EA 0F 02 04 01 02 05 00 03 06 20 22 02 08 01 04 07 64 64 60 02 0D 02 02 0F 01 EF \
        FE DC BA 04 F3 00 07 00 04 04 00 0B 01 03 EF \
        FE DC BA 04 F3 00 06 00 07 03 00 07 01 EF
        """)
        #expect(s.state.firmware == "2.0.2.2")
        #expect(s.state.left == Battery(level: 100, charging: false))
        #expect(s.state.right == Battery(level: 100, charging: false))
        #expect(s.state.caseBattery == Battery(level: 96, charging: false))
        // Strength 0x03 is the 4 Pro's adaptive mode.
        #expect(s.state.adaptiveANC == true)
        #expect(s.state.ancLevel == nil)
        #expect(s.state.equalizer == .voice)

        // A fixed strength turns adaptive off; the event 0x27 (serial number, faked here) is
        // ignored but still acknowledged.
        let acks = feed(&s, """
        FE DC BA C7 F4 00 06 05 04 00 0B 01 01 EF \
        FE DC BA C7 F4 00 18 03 16 00 27 30 30 30 30 30 2F 30 30 30 30 30 30 30 30 30 30 30 30 30 30 EF
        """)
        #expect(s.state.adaptiveANC == false)
        #expect(s.state.ancLevel == .light)
        #expect(acks == [Frame(.response, .notifyConfig, sequence: 5), Frame(.response, .notifyConfig, sequence: 3)])
    }
}

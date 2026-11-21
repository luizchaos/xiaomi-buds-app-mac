// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

@testable import BudsKit
import Testing

/// Adaptive noise cancelling is a separate flag on the 5/6 Pro and a strength value on the
/// 3/4 Pro. These pin the bytes sent for each, so one model's fix can't change the other's.
@Suite struct AdaptiveANCTests {
    @Test func styleFromName() {
        #expect(AdaptiveANCStyle(deviceName: "Redmi Buds 4 Pro") == .strengthLevel)
        #expect(AdaptiveANCStyle(deviceName: "Redmi Buds 3 Pro") == .strengthLevel)
        #expect(AdaptiveANCStyle(deviceName: "Redmi Buds 5 Pro") == .flag)
        #expect(AdaptiveANCStyle(deviceName: "Redmi Buds 6 Pro") == .flag)
        #expect(AdaptiveANCStyle(deviceName: nil) == .flag)
    }

    @Test func flagModelsSendTheSameFramesAsBefore() {
        var s = BudsSession()
        #expect(s.setAdaptiveANC(true).map(\.payload) == [[0x03, 0x00, 0x25, 0x01]])
        #expect(s.setANCLevel(.deep).map(\.payload) == [[0x03, 0x00, 0x25, 0x00], [0x04, 0x00, 0x0B, 0x01, 0x02]])
        // Already off: only the strength is sent.
        #expect(s.setANCLevel(.light).map(\.payload) == [[0x04, 0x00, 0x0B, 0x01, 0x01]])
        // The flag models also request config 0x25 after the handshake.
        #expect(s.refresh().contains { $0.payload == [0x00, 0x25] })
    }

    @Test func strengthModelsNeverUseTheFlag() {
        var s = BudsSession(adaptiveStyle: .strengthLevel)
        #expect(s.setAdaptiveANC(true).map(\.payload) == [[0x04, 0x00, 0x0B, 0x01, 0x03]])
        #expect(s.state.adaptiveANC == true)
        #expect(s.setANCLevel(.deep).map(\.payload) == [[0x04, 0x00, 0x0B, 0x01, 0x02]])
        #expect(s.state.adaptiveANC == false)
        #expect(!s.refresh().contains { $0.payload == [0x00, 0x25] })
    }

    @Test func strengthThreeIsOnlyAdaptiveOnStrengthModels() {
        let notify = Frame(.budsNotify, .notifyConfig, sequence: 1, payload: [0x04, 0x00, 0x0B, 0x01, 0x03])
        var flag = BudsSession()
        _ = flag.handle(notify)
        #expect(flag.state.adaptiveANC == nil)
        #expect(flag.state.ancLevel == nil)

        var strength = BudsSession(adaptiveStyle: .strengthLevel)
        _ = strength.handle(notify)
        #expect(strength.state.adaptiveANC == true)
    }
}

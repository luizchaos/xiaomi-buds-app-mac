// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

@testable import BudsKit
import Testing

@Suite struct FrameTests {
    @Test func encodesRequest() {
        let f = Frame(.hostRequest, .anc, sequence: 0x05, payload: [0x02, 0x04, 0x01])
        #expect(f.encoded() == [0xFE, 0xDC, 0xBA, 0xC4, 0x08, 0x00, 0x04, 0x05, 0x02, 0x04, 0x01, 0xEF])
    }

    @Test func encodesResponseWithStatusByte() {
        let f = Frame(.response, .reportStatus, sequence: 0x09)
        #expect(f.encoded() == [0xFE, 0xDC, 0xBA, 0x04, 0x0E, 0x00, 0x02, 0x00, 0x09, 0xEF])
    }

    @Test func roundTripsAndSplitsStream() {
        let a = Frame(.hostRequest, .getConfig, sequence: 1, payload: [0x00, 0x07])
        let b = Frame(.response, .getConfig, sequence: 2, payload: [0x03, 0x00, 0x07, 0x05])
        let stream = [0x00, 0x11] + a.encoded() + b.encoded()
        var parser = FrameParser()
        // Split mid-frame to exercise reassembly.
        let first = parser.feed(Array(stream.prefix(9)))
        let rest = parser.feed(Array(stream.dropFirst(9)))
        #expect(first.isEmpty)
        #expect(rest == [a, b])
    }
}

@Suite struct SessionTests {
    private func budsFrame(_ op: Opcode, _ payload: [UInt8], seq: UInt8 = 0x10) -> Frame {
        Frame(.budsRequest, op, sequence: seq, payload: payload)
    }

    @Test func handshakeReachesReady() {
        var s = BudsSession()
        let hello = s.start()
        #expect(hello.first?.opcode == .authChallenge)
        #expect(hello.first?.payload.count == 17)

        let confirm = s.handle(Frame(.response, .authChallenge, sequence: 0, payload: [0x01] + Array(repeating: 0, count: 16)))
        #expect(confirm.first?.opcode == .authConfirm)

        let answer = s.handle(budsFrame(.authChallenge, [0x01] + Array(0..<16)))
        #expect(answer.first?.type == .response)
        #expect(answer.first?.sequence == 0x10)
        #expect(answer.first?.payload.count == 17)

        let after = s.handle(budsFrame(.authConfirm, [0x01]))
        #expect(s.phase == .ready)
        #expect(after.contains { $0.opcode == .getDeviceInfo })
    }

    @Test func decodesBatteryStatusAndAcks() {
        var s = BudsSession()
        // left 80 %, right 75 % charging, case absent; then noise mode = ANC
        let acks = s.handle(Frame(.budsNotify, .reportStatus, sequence: 3,
                                  payload: [0x04, 0x00, 0x50, 0xCB, 0xFF, 0x02, 0x04, 0x01]))
        #expect(s.state.left == Battery(level: 80, charging: false))
        #expect(s.state.right == Battery(level: 75, charging: true))
        #expect(s.state.caseBattery == nil)
        #expect(s.state.noiseMode == .noiseCancelling)
        #expect(acks == [Frame(.response, .reportStatus, sequence: 3)])
    }

    @Test func decodesWearEventAndAcks() {
        var s = BudsSession()
        let raw: [UInt8] = [0xFE, 0xDC, 0xBA, 0x87, 0xF4, 0x00, 0x05, 0x02, 0x03, 0x00, 0x0C, 0x0C, 0xEF]
        var parser = FrameParser()
        let frames = parser.feed(raw)
        #expect(frames.first?.sequence == 0x02)
        let acks = s.handle(frames[0])
        #expect(s.state.leftInEar == true && s.state.rightInEar == true)
        #expect(acks == [Frame(.response, .notifyConfig, sequence: 0x02)])
    }

    @Test func decodesConfig() {
        var s = BudsSession()
        _ = s.handle(Frame(.response, .getConfig, sequence: 1, payload: [0x04, 0x00, 0x0B, 0x02, 0x01]))
        _ = s.handle(Frame(.response, .getConfig, sequence: 2, payload: [0x03, 0x00, 0x07, 0x05]))
        #expect(s.state.transparencyLevel == .voice)
        #expect(s.state.equalizer == .bass)
    }

    @Test func authResponseIsDeterministic() {
        let challenge: [UInt8] = Array(0..<16)
        #expect(BudsAuth.response(to: challenge) == BudsAuth.response(to: challenge))
        #expect(BudsAuth.response(to: challenge) != BudsAuth.response(to: Array(repeating: 0, count: 16)))
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation

/// Message direction/kind byte. Bit 0x80 marks a request; responses (0x04) carry an extra
/// status byte. Seen from the 6 Pro: C0 (auth), C7 and 87 (events) for buds → host.
public enum FrameType: UInt8, Sendable {
    case hostRequest = 0xC4
    case response = 0x04
    case budsRequest = 0xC0
    case budsNotify = 0xC7
    case budsEvent = 0x87
}

public enum Opcode: UInt8, Sendable {
    case getDeviceInfo = 0x02
    case anc = 0x08
    case getRunInfo = 0x09
    case reportStatus = 0x0E
    case authChallenge = 0x50
    case authConfirm = 0x51
    case setConfig = 0xF2
    case getConfig = 0xF3
    case notifyConfig = 0xF4
}

/// One protocol frame:
///
///     FE DC BA | type | opcode | len (u16 BE) | [status, responses only] | seq | payload… | EF
///
/// `len` counts the optional status byte, the sequence byte and the payload.
public struct Frame: Equatable, Sendable {
    static let header: [UInt8] = [0xFE, 0xDC, 0xBA]
    static let trailer: UInt8 = 0xEF
    /// header(3) + type + opcode + len(2) + trailer
    static let overhead = 8

    public var typeCode: UInt8
    public var opcodeCode: UInt8
    public var status: UInt8
    public var sequence: UInt8
    public var payload: [UInt8]

    public var type: FrameType? { FrameType(rawValue: typeCode) }
    public var opcode: Opcode? { Opcode(rawValue: opcodeCode) }
    var isRequest: Bool { typeCode & 0x80 != 0 }

    public init(_ type: FrameType, _ opcode: Opcode, sequence: UInt8, payload: [UInt8] = [], status: UInt8 = 0) {
        self.typeCode = type.rawValue
        self.opcodeCode = opcode.rawValue
        self.status = status
        self.sequence = sequence
        self.payload = payload
    }

    init(typeCode: UInt8, opcodeCode: UInt8, status: UInt8, sequence: UInt8, payload: [UInt8]) {
        self.typeCode = typeCode
        self.opcodeCode = opcodeCode
        self.status = status
        self.sequence = sequence
        self.payload = payload
    }

    public func encoded() -> [UInt8] {
        let prefix = isRequest ? 1 : 2
        let length = payload.count + prefix
        var out = Frame.header
        out.reserveCapacity(Frame.overhead + length)
        out += [typeCode, opcodeCode, UInt8(length >> 8), UInt8(length & 0xFF)]
        if !isRequest { out.append(status) }
        out.append(sequence)
        out += payload
        out.append(Frame.trailer)
        return out
    }
}

/// Reassembles frames from an RFCOMM byte stream. Several frames may arrive in one
/// packet, and one frame may be split across packets.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while true {
            guard let start = headerIndex() else {
                // Keep a possible partial header at the end.
                buffer = Array(buffer.suffix(2))
                return frames
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 7 else { return frames }
            let length = Int(buffer[5]) << 8 | Int(buffer[6])
            let total = Frame.overhead + length
            guard buffer.count >= total else { return frames }

            let raw = Array(buffer[0..<total])
            buffer.removeFirst(total)
            if let frame = Self.decode(raw) { frames.append(frame) }
        }
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 3 else { return nil }
        for i in 0...(buffer.count - 3)
        where buffer[i] == 0xFE && buffer[i + 1] == 0xDC && buffer[i + 2] == 0xBA {
            return i
        }
        return nil
    }

    static func decode(_ raw: [UInt8]) -> Frame? {
        guard raw.count >= 9, raw.last == Frame.trailer else { return nil }
        let typeCode = raw[3]
        let isRequest = typeCode & 0x80 != 0
        let payloadStart = isRequest ? 8 : 9
        guard raw.count >= payloadStart + 1 else { return nil }
        return Frame(
            typeCode: typeCode,
            opcodeCode: raw[4],
            status: isRequest ? 0 : raw[7],
            sequence: raw[payloadStart - 1],
            payload: Array(raw[payloadStart..<(raw.count - 1)])
        )
    }
}

extension Array where Element == UInt8 {
    public var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

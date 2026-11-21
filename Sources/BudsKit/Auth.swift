// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation
import Security

/// Challenge/response used by the earbuds before they accept commands.
///
/// It is a SAFER+ variant (128-bit key, 8 rounds) as used by Bluetooth's E1 function:
/// the 16-byte challenge from the earbuds is the key, and a fixed block is encrypted
/// with it. Constants and structure are ported from Gadgetbridge
/// (service/devices/redmibuds/protocol/Authentication.java and AuthData.java,
/// https://codeberg.org/Freeyourgadget/Gadgetbridge, AGPL-3.0-or-later).
enum BudsAuth {
    /// Positions where SAFER+ uses XOR / exp; the others use addition / log.
    private static let xorMask: UInt16 = 0x9999

    private static let plaintext: [UInt8] = [
        0x11, 0x22, 0x33, 0x33, 0x22, 0x11, 0x11, 0x22,
        0x33, 0x33, 0x22, 0x11, 0x11, 0x22, 0x33, 0x33,
    ]

    /// SAFER+ pseudo-Hadamard transform, row by row.
    private static let mix: [[UInt8]] = [
        [2, 1, 1, 1, 4, 2, 1, 1, 2, 2, 4, 2, 4, 4, 16, 8],
        [2, 1, 1, 1, 4, 2, 1, 1, 1, 1, 2, 1, 2, 2, 8, 4],
        [1, 1, 4, 2, 2, 2, 4, 2, 16, 8, 4, 4, 2, 1, 1, 1],
        [1, 1, 4, 2, 1, 1, 2, 1, 8, 4, 2, 2, 2, 1, 1, 1],
        [16, 8, 2, 2, 4, 2, 4, 4, 1, 1, 4, 2, 1, 1, 2, 1],
        [8, 4, 1, 1, 2, 1, 2, 2, 1, 1, 4, 2, 1, 1, 2, 1],
        [2, 2, 4, 2, 4, 4, 16, 8, 2, 1, 1, 1, 4, 2, 1, 1],
        [1, 1, 2, 1, 2, 2, 8, 4, 2, 1, 1, 1, 4, 2, 1, 1],
        [4, 2, 4, 4, 16, 8, 2, 2, 1, 1, 2, 1, 1, 1, 4, 2],
        [2, 1, 2, 2, 8, 4, 1, 1, 1, 1, 2, 1, 1, 1, 4, 2],
        [4, 4, 16, 8, 1, 1, 2, 1, 4, 2, 1, 1, 4, 2, 2, 2],
        [2, 2, 8, 4, 1, 1, 2, 1, 4, 2, 1, 1, 2, 1, 1, 1],
        [1, 1, 2, 1, 1, 1, 4, 2, 4, 4, 16, 8, 2, 2, 4, 2],
        [1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 8, 4, 1, 1, 2, 1],
        [4, 2, 1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 16, 8, 4, 4],
        [4, 2, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 8, 4, 2, 2],
    ]

    private static func powMod(_ base: Int, _ exp: Int, _ mod: Int) -> Int {
        var result = 1, b = base % mod, e = exp
        while e > 0 {
            if e & 1 == 1 { result = result * b % mod }
            b = b * b % mod
            e >>= 1
        }
        return result
    }

    /// exp[i] = 45^i mod 257 (256 maps to 0).
    private static let expTable: [UInt8] = (0..<256).map { UInt8(powMod(45, $0, 257) & 0xFF) }

    /// Inverse of `expTable`.
    private static let logTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { table[Int(expTable[i])] = UInt8(i) }
        return table
    }()

    private static let bias: [[UInt8]] = (0..<16).map { i in
        (0..<16).map { j in
            let inner = powMod(45, 17 * (i + 2) + (j + 1), 257)
            return UInt8(powMod(45, inner, 257) & 0xFF)
        }
    }

    private static func isXor(_ i: Int) -> Bool { (1 << i) & Int(xorMask) != 0 }

    private static func keySchedule(_ challenge: [UInt8]) -> [[UInt8]] {
        var key = challenge
        key[15] ^= 6
        var register = key + [key.reduce(0, ^)]
        var keys = [key]
        for k in 1...16 {
            for i in 0..<17 { register[i] = (register[i] << 3) | (register[i] >> 5) }
            keys.append((0..<16).map { register[(k + $0) % 17] &+ bias[k - 1][$0] })
        }
        return keys
    }

    static func response(to challenge: [UInt8]) -> [UInt8] {
        precondition(challenge.count == 16)
        let keys = keySchedule(challenge)
        var block = plaintext

        for round in 0..<8 {
            if round == 2 {
                for i in 0..<16 {
                    block[i] = isXor(i) ? block[i] ^ plaintext[i] : block[i] &+ plaintext[i]
                }
            }
            let k1 = keys[round * 2], k2 = keys[round * 2 + 1]
            for i in 0..<16 {
                block[i] = isXor(i) ? block[i] ^ k1[i] : block[i] &+ k1[i]
                block[i] = isXor(i) ? expTable[Int(block[i])] : logTable[Int(block[i])]
                block[i] = isXor(i) ? block[i] &+ k2[i] : block[i] ^ k2[i]
            }
            let copy = block
            for i in 0..<16 {
                var sum: UInt8 = 0
                for j in 0..<16 { sum = sum &+ (mix[i][j] &* copy[j]) }
                block[i] = sum
            }
        }

        let last = keys[16]
        return (0..<16).map { isXor($0) ? last[$0] ^ block[$0] : last[$0] &+ block[$0] }
    }

    static func randomChallenge() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes
    }
}

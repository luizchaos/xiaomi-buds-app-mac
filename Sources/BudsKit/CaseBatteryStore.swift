// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation

/// The last case battery level the earbuds reported, and when.
///
/// Most models only report the case while an earbud sits in it: once both are in the ear the
/// value comes back as "unavailable". Keeping the last reading lets the app still show it.
public struct CaseBatteryReading: Codable, Equatable, Sendable {
    public var level: Int
    public var date: Date

    public init(level: Int, date: Date) {
        self.level = level
        self.date = date
    }
}

/// Persists the last case reading per pair of earbuds (keyed by Bluetooth address), so it
/// survives restarts and one pair's case never shows up for another.
public struct CaseBatteryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "lastCaseBattery."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(for deviceID: String) -> CaseBatteryReading? {
        guard let data = defaults.data(forKey: Self.keyPrefix + deviceID) else { return nil }
        return try? JSONDecoder().decode(CaseBatteryReading.self, from: data)
    }

    public func save(_ reading: CaseBatteryReading, for deviceID: String) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        defaults.set(data, forKey: Self.keyPrefix + deviceID)
    }
}

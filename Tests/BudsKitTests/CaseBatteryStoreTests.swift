// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

@testable import BudsKit
import Foundation
import Testing

@Suite struct CaseBatteryStoreTests {
    /// A throwaway defaults domain per test, so nothing touches the real app settings.
    private func makeStore() -> (CaseBatteryStore, UserDefaults, String) {
        let suite = "CaseBatteryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (CaseBatteryStore(defaults: defaults), defaults, suite)
    }

    @Test func savesAndLoadsPerDevice() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(CaseBatteryReading(level: 85, date: date), for: "00-bb-43-8a-89-45")
        #expect(store.load(for: "00-bb-43-8a-89-45") == CaseBatteryReading(level: 85, date: date))
        // Another pair of earbuds has its own case.
        #expect(store.load(for: "48-73-cb-5b-35-cb") == nil)
    }

    @Test func newReadingReplacesTheOldOne() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(CaseBatteryReading(level: 85, date: Date(timeIntervalSince1970: 1)), for: "a")
        store.save(CaseBatteryReading(level: 60, date: Date(timeIntervalSince1970: 2)), for: "a")
        #expect(store.load(for: "a")?.level == 60)
    }

    @Test func survivesANewStoreInstance() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(CaseBatteryReading(level: 42, date: Date(timeIntervalSince1970: 3)), for: "a")
        #expect(CaseBatteryStore(defaults: defaults).load(for: "a")?.level == 42)
    }
}

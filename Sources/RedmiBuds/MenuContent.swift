// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import BudsKit
import SwiftUI

struct MenuContent: View {
    @Bindable var controller: BudsController
    @State private var showMore = false
    @State private var finding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if controller.connection == .ready {
                BatteryRow(state: controller.state, lastCase: controller.lastCaseBattery)
                Divider()
                noiseControl
                Divider()
                DisclosureGroup(isExpanded: $showMore) {
                    moreSettings.padding(.top, 8)
                } label: {
                    Text("settings.more")
                }
            } else {
                statusMessage
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: UISnapshot.toggleMoreSettings)) { _ in
            showMore.toggle()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "earbuds").font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.deviceName ?? "Redmi Buds").font(.headline)
                Text(controller.connection.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.connection {
            case .searching, .connecting, .authenticating:
                ProgressView().controlSize(.small)
            case .notPaired:
                Text("message.notPaired")
            case .disconnected:
                Text("message.disconnected")
            case .failed(let error):
                Text(error.localizedMessage)
                Button("action.retry") { controller.connect() }
            case .ready:
                EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Noise control

    private var noiseControl: some View {
        let state = controller.state
        return VStack(alignment: .leading, spacing: 10) {
            Text("noise.title").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach([NoiseMode.noiseCancelling, .transparency, .off]) { mode in
                    ModeButton(mode: mode, selected: state.noiseMode == mode) {
                        controller.setNoiseMode(mode)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            // The pickers keep their titles for VoiceOver, but hide them visually: a segmented
            // picker in a 320 pt menu has no room for a leading label (it got truncated).
            switch state.noiseMode {
            case .noiseCancelling:
                Picker("noise.ancLevel", selection: ancBinding) {
                    ForEach(ANCChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            case .transparency:
                Picker("noise.transparencyLevel", selection: transparencyBinding) {
                    ForEach(TransparencyLevel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            default:
                EmptyView()
            }
        }
    }

    private var ancBinding: Binding<ANCChoice> {
        Binding {
            let s = controller.state
            if s.adaptiveANC == true { return .adaptive }
            return s.ancLevel.map(ANCChoice.level) ?? .level(.balanced)
        } set: { choice in
            switch choice {
            case .adaptive: controller.setAdaptiveANC(true)
            case .level(let level): controller.setANCLevel(level)
            }
        }
    }

    private var transparencyBinding: Binding<TransparencyLevel> {
        Binding { controller.state.transparencyLevel ?? .regular } set: { controller.setTransparencyLevel($0) }
    }

    // MARK: More settings

    private var moreSettings: some View {
        let s = controller.state
        return VStack(alignment: .leading, spacing: 8) {
            Picker("settings.equalizer", selection: Binding {
                s.equalizer ?? .standard
            } set: { controller.setEqualizer($0) }) {
                ForEach(EqualizerPreset.allCases) { Text($0.label).tag($0) }
            }

            toggle("settings.earDetection", s.earDetection, controller.setEarDetection)
            toggle("settings.adaptiveSound", s.adaptiveSound, controller.setAdaptiveSound)
            toggle("settings.dualConnection", s.dualConnection, controller.setDualConnection)
            toggle("settings.autoAnswer", s.autoAnswer, controller.setAutoAnswer)

            Button(finding ? "settings.find.stop" : "settings.find.start") {
                finding ? controller.stopFind() : controller.startFind()
                finding.toggle()
            }
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ value: Bool?, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding { value ?? false } set: { set($0) })
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(value == nil)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("action.refresh") { controller.connection == .ready ? controller.refresh() : controller.connect() }
            Spacer()
            Button("action.quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

// MARK: - Components

struct BatteryRow: View {
    let state: BudsState
    let lastCase: CaseBatteryReading?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            BatteryGauge(title: "battery.left", symbol: "earbuds", battery: state.left, inEar: state.leftInEar)
            BatteryGauge(title: "battery.right", symbol: "earbuds", battery: state.right, inEar: state.rightInEar)
            caseGauge
        }
    }

    /// The case is usually only reported while an earbud is in it, so fall back to the last
    /// reading and say how old it is.
    @ViewBuilder private var caseGauge: some View {
        if let live = state.caseBattery {
            BatteryGauge(title: "battery.case", symbol: "earbuds.case", battery: live, inEar: nil)
        } else if let lastCase {
            BatteryGauge(title: "battery.case", symbol: "earbuds.case",
                         battery: Battery(level: lastCase.level, charging: false), inEar: nil, lastSeen: lastCase.date)
        } else {
            BatteryGauge(title: "battery.case", symbol: "earbuds.case", battery: nil, inEar: nil)
        }
    }
}

struct BatteryGauge: View {
    let title: LocalizedStringKey
    let symbol: String
    let battery: Battery?
    let inEar: Bool?
    /// Set when `battery` is a remembered value rather than a live one.
    var lastSeen: Date? = nil

    var body: some View {
        VStack(spacing: 4) {
            Gauge(value: Double(battery?.level ?? 0), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: battery?.charging == true ? "bolt.fill" : symbol)
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .opacity(battery == nil ? 0.35 : lastSeen == nil ? 1 : 0.55)

            Text(battery.map { "\($0.level)%" } ?? "--").font(.callout.monospacedDigit().weight(.medium))
            HStack(spacing: 3) {
                Text(title)
                if inEar == true {
                    Image(systemName: "ear").accessibilityLabel(Text("battery.inEar"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let lastSeen {
                // "5 min ago", localized by the system; refreshed every minute.
                TimelineView(.everyMinute) { _ in
                    Text(lastSeen, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        guard let battery else { return .gray }
        if lastSeen != nil { return .secondary }
        if battery.charging { return .green }
        return battery.level <= 20 ? .red : .accentColor
    }
}

struct ModeButton: View {
    let mode: NoiseMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode == .off ? "speaker.slash" : Optional(mode).symbol)
                    .font(.title3)
                    .frame(height: 22)
                // Long single words (German "Geräuschunterdrückung") wrap at the soft hyphen
                // in the string instead of being truncated.
                Text(mode.label)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// ANC strength plus the adaptive mode, shown as one picker.
enum ANCChoice: Hashable, CaseIterable, Identifiable {
    case level(ANCLevel)
    case adaptive

    static let allCases: [ANCChoice] = [.level(.light), .level(.balanced), .level(.deep), .adaptive]
    var id: Self { self }

    var label: String {
        switch self {
        case .adaptive: String(localized: "noise.ancLevel.adaptive")
        case .level(let level): level.label
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import AppKit
import BudsKit

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--cli") {
            CLI.run(Array(args[(i + 1)...]))
        } else {
            AppDelegate.runApp()
        }
    }
}

/// Headless mode for debugging and scripting (output is English only):
/// `RedmiBuds --cli [status|anc|transparency|off|anc-light|anc-balanced|anc-deep|anc-adaptive|find|stop-find|eq <preset>|raw <opcode> <bytes…>] [-v]`
@MainActor
enum CLI {
    static func run(_ args: [String]) {
        let verbose = args.contains("-v")
        let words = args.filter { $0 != "-v" }
        let command = words.first ?? "status"
        rawArguments = Array(words.dropFirst())
        let controller = BudsController()
        var done = false

        controller.onLog = { line in
            if verbose || !line.hasPrefix("←") && !line.hasPrefix("→") { fputs("· \(line)\n", stderr) }
        }
        controller.onChange = {
            switch controller.connection {
            case .notPaired, .disconnected, .failed:
                print("state: \(controller.connection)")
                done = true
            case .ready where !done:
                done = true
                Task { @MainActor in
                    // Give the config responses time to arrive.
                    try? await Task.sleep(for: .seconds(1.5))
                    execute(command, words.dropFirst().first, on: controller)
                    try? await Task.sleep(for: .seconds(1.5))
                    printState(controller)
                    exit(0)
                }
            default:
                break
            }
        }

        controller.start()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            if done, controller.connection != .ready { exit(1) }
        }
        print("timed out: \(controller.connection)")
        exit(2)
    }

    private static var rawArguments: [String] = []

    private static func execute(_ command: String, _ argument: String?, on c: BudsController) {
        switch command {
        case "anc": c.setNoiseMode(.noiseCancelling)
        case "transparency": c.setNoiseMode(.transparency)
        case "off": c.setNoiseMode(.off)
        case "anc-light": c.setANCLevel(.light)
        case "anc-balanced": c.setANCLevel(.balanced)
        case "anc-deep": c.setANCLevel(.deep)
        case "anc-adaptive": c.setAdaptiveANC(true)
        case "find": c.startFind()
        case "stop-find": c.stopFind()
        case "raw":
            // raw <opcode> <payload bytes…>, all hex, e.g. `raw F2 04 00 0B 01 03`.
            let bytes = rawArguments.compactMap { UInt8($0, radix: 16) }
            if let first = bytes.first, let opcode = Opcode(rawValue: first) { c.sendRaw(opcode, Array(bytes.dropFirst())) }
        case "eq":
            if let preset = EqualizerPreset.allCases.first(where: { "\($0)" == argument }) { c.setEqualizer(preset) }
        default: break
        }
    }

    private static func printState(_ c: BudsController) {
        let s = c.state
        func bat(_ b: Battery?) -> String {
            guard let b else { return "--" }
            return "\(b.level)%\(b.charging ? " (charging)" : "")"
        }
        func show<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "?" }
        func caseLine(_ live: Battery?, _ last: CaseBatteryReading?) -> String {
            if let live { return bat(live) }
            guard let last else { return "--" }
            let age = last.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(Locale(identifier: "en_US")))
            return "-- (last seen \(last.level)%, \(age))"
        }
        print("""
        device:          \(c.deviceName ?? "?")  firmware \(s.firmware ?? "?")
        left:            \(bat(s.left))  in ear: \(show(s.leftInEar))
        right:           \(bat(s.right))  in ear: \(show(s.rightInEar))
        case:            \(caseLine(s.caseBattery, c.lastCaseBattery))
        mode:            \(show(s.noiseMode))
        anc level:       \(show(s.ancLevel))  adaptive: \(show(s.adaptiveANC))
        transparency:    \(show(s.transparencyLevel))
        equalizer:       \(show(s.equalizer))
        ear detection:   \(show(s.earDetection))
        adaptive sound:  \(show(s.adaptiveSound))
        dual connection: \(show(s.dualConnection))
        auto answer:     \(show(s.autoAnswer))
        """)
    }
}

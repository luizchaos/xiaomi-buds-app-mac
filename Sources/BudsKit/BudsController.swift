// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Henrique Carvalho

import Foundation
@preconcurrency import IOBluetooth
import Observation
import os

/// Finds the paired Redmi Buds, opens the vendor RFCOMM channel and keeps `state` current.
/// All IOBluetooth callbacks arrive on the main run loop, so the whole class is main-actor.
/// Why the connection failed. User-facing text lives in the app's localization files.
public enum BudsError: Error, Equatable, Sendable {
    /// The SDP query could not be started.
    case sdpQueryFailed(code: IOReturn)
    /// The earbuds don't advertise the vendor control service (0xFD2D).
    case serviceNotFound
    /// IOBluetooth refused to open the RFCOMM channel.
    case channelOpenFailed(code: IOReturn)
    /// The earbuds rejected the channel, usually because a phone running the
    /// Xiaomi Earbuds app already holds it.
    case channelRejected
    /// The channel opened but the handshake never finished.
    case authenticationTimedOut
}

@MainActor
@Observable
public final class BudsController {
    public enum Connection: Equatable, Sendable {
        case searching
        case notPaired
        case disconnected
        case connecting
        case authenticating
        case ready
        case failed(BudsError)
    }

    public private(set) var connection: Connection = .searching
    public private(set) var state = BudsState()
    public private(set) var deviceName: String?
    public private(set) var log: [String] = []

    /// Called for every log line (used by the CLI to echo to the terminal).
    @ObservationIgnored public var onLog: ((String) -> Void)?
    /// Called whenever `connection` or `state` changes.
    @ObservationIgnored public var onChange: (() -> Void)?

    /// Matches the advertised name; Gadgetbridge drives the 3 Pro … 8 Active the same way.
    @ObservationIgnored public var namePattern = "Redmi Buds"

    /// Service UUID of the vendor control channel.
    static let serviceUUID = IOBluetoothSDPUUID(uuid16: 0xFD2D)!

    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var channel: IOBluetoothRFCOMMChannel?
    @ObservationIgnored private var session = BudsSession()
    @ObservationIgnored private var parser = FrameParser()
    @ObservationIgnored private var bridge: DelegateBridge!
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var handshakeTimeout: Task<Void, Never>?
    @ObservationIgnored private var refreshTimer: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "dev.local.RedmiBuds", category: "bluetooth")

    public init() {
        bridge = DelegateBridge(owner: self)
    }

    // MARK: - Lifecycle

    public func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: bridge, selector: #selector(DelegateBridge.deviceConnected(_:device:)))
        connect()
    }

    public func connect() {
        retryTask?.cancel()
        guard let device = findDevice() else {
            update(.notPaired)
            log("No paired device matching \"\(namePattern)\"")
            return
        }
        self.device = device
        deviceName = device.name
        disconnectNotification?.unregister()
        disconnectNotification = device.register(
            forDisconnectNotification: bridge, selector: #selector(DelegateBridge.deviceDisconnected(_:device:)))

        guard device.isConnected() else {
            update(.disconnected)
            log("\(device.name ?? "Device") is paired but not connected")
            return
        }
        guard channel == nil else { return }
        update(.connecting)
        openChannel()
    }

    public func disconnect() {
        teardown()
        update(.disconnected)
    }

    private func findDevice() -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let matches = paired.filter { $0.name?.localizedCaseInsensitiveContains(namePattern) == true }
        return matches.first(where: { $0.isConnected() }) ?? matches.first
    }

    private func openChannel() {
        guard let device else { return }
        guard let channelID = rfcommChannelID(device) else {
            log("Running SDP query…")
            let kr = device.performSDPQuery(bridge, uuids: [Self.serviceUUID])
            if kr != kIOReturnSuccess { fail(.sdpQueryFailed(code: kr)) }
            return
        }

        log("Opening RFCOMM channel \(channelID)")
        var opened: IOBluetoothRFCOMMChannel?
        let kr = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: bridge)
        guard kr == kIOReturnSuccess, let opened else {
            fail(.channelOpenFailed(code: kr))
            return
        }
        channel = opened

        // If the earbuds reject the channel, IOBluetooth may never call back.
        handshakeTimeout?.cancel()
        handshakeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, self.connection == .connecting else { return }
            self.fail(.channelRejected)
        }
    }

    private func rfcommChannelID(_ device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        guard let record = device.getServiceRecord(for: Self.serviceUUID) else { return nil }
        var id: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? id : nil
    }

    fileprivate func sdpQueryComplete(status: IOReturn) {
        guard let device, status == kIOReturnSuccess, rfcommChannelID(device) != nil else {
            fail(.serviceNotFound)
            return
        }
        openChannel()
    }

    fileprivate func channelOpened(status: IOReturn) {
        guard status == kIOReturnSuccess, let channel else {
            self.channel = nil
            fail(.channelOpenFailed(code: status))
            return
        }
        log("RFCOMM open (MTU \(channel.getMTU()))")
        parser = FrameParser()
        update(.authenticating)
        send(session.start())

        handshakeTimeout?.cancel()
        handshakeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.connection == .authenticating else { return }
            self.fail(.authenticationTimedOut)
        }
    }

    fileprivate func channelClosed() {
        log("RFCOMM closed")
        channel = nil
        stopTimers()
        if connection == .ready || connection == .authenticating { scheduleRetry() }
    }

    fileprivate func deviceConnected(_ device: IOBluetoothDevice) {
        guard device.name?.localizedCaseInsensitiveContains(namePattern) == true else { return }
        log("\(device.name ?? "Device") connected")
        // Give the audio profiles a moment before opening our channel.
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    fileprivate func deviceDisconnected(_ device: IOBluetoothDevice) {
        log("\(device.name ?? "Device") disconnected")
        teardown()
        update(.disconnected)
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.channel == nil else { return }
            self.connect()
        }
    }

    private func teardown() {
        stopTimers()
        retryTask?.cancel()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        session = BudsSession()
        state = BudsState()
    }

    private func stopTimers() {
        handshakeTimeout?.cancel()
        refreshTimer?.cancel()
    }

    private func fail(_ error: BudsError) {
        log("Error: \(error)")
        teardown()
        update(.failed(error))
    }

    // MARK: - Data

    fileprivate func received(_ bytes: [UInt8]) {
        log("← \(bytes.hex)", debug: true)
        for frame in parser.feed(bytes) {
            let wasReady = session.phase == .ready
            send(session.handle(frame))
            syncState()
            if !wasReady && session.phase == .ready { didBecomeReady() }
        }
    }

    private func didBecomeReady() {
        handshakeTimeout?.cancel()
        update(.ready)
        log("Authenticated")
        // Batteries are pushed on change, but a periodic refresh catches anything missed.
        refreshTimer?.cancel()
        refreshTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private func send(_ frames: [Frame]) {
        guard let channel else { return }
        for frame in frames {
            var bytes = frame.encoded()
            log("→ \(bytes.hex)", debug: true)
            let kr = bytes.withUnsafeMutableBytes { buffer in
                channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
            }
            if kr != kIOReturnSuccess { log("Write failed (\(kr))") }
        }
    }

    private func syncState() {
        if state != session.state {
            state = session.state
            onChange?()
        }
    }

    private func update(_ new: Connection) {
        guard connection != new else { return }
        connection = new
        onChange?()
    }

    private func log(_ line: String, debug: Bool = false) {
        if debug { logger.debug("\(line, privacy: .public)") } else { logger.info("\(line, privacy: .public)") }
        log.append(line)
        if log.count > 300 { log.removeFirst(log.count - 300) }
        onLog?(line)
    }

    // MARK: - Commands

    private func perform(_ body: (inout BudsSession) -> [Frame]) {
        guard connection == .ready else { return }
        send(body(&session))
        syncState()
    }

    public func refresh() { perform { $0.refresh() } }
    public func setNoiseMode(_ mode: NoiseMode) { perform { $0.setNoiseMode(mode) } }
    public func setANCLevel(_ level: ANCLevel) { perform { $0.setANCLevel(level) } }
    public func setAdaptiveANC(_ on: Bool) { perform { $0.setAdaptiveANC(on) } }
    public func setTransparencyLevel(_ level: TransparencyLevel) { perform { $0.setTransparencyLevel(level) } }
    public func setEqualizer(_ preset: EqualizerPreset) { perform { $0.setEqualizer(preset) } }
    public func setEarDetection(_ on: Bool) { perform { $0.setEarDetection(on) } }
    public func setAdaptiveSound(_ on: Bool) { perform { $0.setAdaptiveSound(on) } }
    public func setDualConnection(_ on: Bool) { perform { $0.setDualConnection(on) } }
    public func setAutoAnswer(_ on: Bool) { perform { $0.setAutoAnswer(on) } }
    public func startFind(_ which: Earbud = .both) { perform { $0.startFind(which) } }
    public func stopFind() { perform { $0.stopFind() } }
}

/// NSObject target for IOBluetooth's delegate/selector callbacks, forwarding to the controller.
private final class DelegateBridge: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    weak var owner: BudsController?

    @MainActor init(owner: BudsController) { self.owner = owner }

    private func onMain(_ body: @MainActor (BudsController) -> Void) {
        MainActor.assumeIsolated {
            guard let owner else { return }
            body(owner)
        }
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        onMain { $0.received(bytes) }
    }

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMain { $0.channelOpened(status: error) }
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        onMain { $0.channelClosed() }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        onMain { $0.sdpQueryComplete(status: status) }
    }

    @objc func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onMain { $0.deviceConnected(device) }
    }

    @objc func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onMain { $0.deviceDisconnected(device) }
    }
}

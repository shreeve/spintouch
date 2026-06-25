import Foundation
import CoreBluetooth

enum ConnectionPhase: Equatable {
    case bluetoothOff
    case idle
    case scanning
    case connecting
    case discovering
    case waitingForTest   // connected, subscribed, waiting for a result
    case reading
    case gotReading
    case failed(String)

    var label: String {
        switch self {
        case .bluetoothOff: return "Bluetooth is off"
        case .idle: return "Ready"
        case .scanning: return "Scanning for SpinTouch…"
        case .connecting: return "Connecting…"
        case .discovering: return "Discovering services…"
        case .waitingForTest: return "Connected — waiting for a test result"
        case .reading: return "Reading results…"
        case .gotReading: return "Results received"
        case .failed(let m): return "Error: \(m)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .discovering, .reading: return true
        default: return false
        }
    }
}

/// Drives the full SpinTouch BLE flow:
/// scan -> connect -> discover -> subscribe(status) -> read(data) -> parse -> ack.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var reading: SpinTouchReading?
    @Published private(set) var deviceName: String?
    @Published private(set) var isConnected = false
    @Published private(set) var log: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var ackChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    private var wantsScan = false
    private var seen: Set<UUID> = []
    private var autoDisconnectTask: Task<Void, Never>?
    private let autoDisconnectDelaySeconds: UInt64 = 8
    private var timeoutTask: Task<Void, Never>?
    private let connectTimeoutSeconds: UInt64 = 30

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public control

    func startScan() {
        autoDisconnectTask?.cancel()
        reading = nil
        // Drop any lingering connection (e.g. the post-reading auto-disconnect
        // window) before rescanning, otherwise didDiscover ignores everything
        // while we still hold a peripheral and the scan times out.
        if peripheral != nil { resetConnectionState() }
        switch central.state {
        case .poweredOn:
            beginScan()
        case .poweredOff, .unauthorized, .unsupported:
            phase = .bluetoothOff
        default:
            // Still initializing; scan once powered on.
            wantsScan = true
            phase = .scanning
        }
    }

    func disconnect() {
        autoDisconnectTask?.cancel()
        resetConnectionState()
        phase = .idle
    }

    // MARK: - Internals

    private func beginScan() {
        wantsScan = false
        phase = .scanning
        seen.removeAll()
        // Scan for everything (nil), then match by name or advertised service.
        // The SpinTouch often advertises only its name, not the 128-bit service
        // UUID, so a service-filtered scan would miss it.
        addLog("Scanning (all devices, matching name \"SpinTouch\" or service)")
        central.scanForPeripherals(withServices: nil, options: nil)
        startTimeout(connectTimeoutSeconds,
                     "Couldn't find or connect to a SpinTouch. Make sure it's on a results screen and the LaMotte app is closed.")
    }

    /// Tear down the current connection (used on terminal failures and before a
    /// rescan) so a later scan can connect again. Cancels any live peripheral
    /// connection — not just the local reference — so iOS doesn't stay connected
    /// to the SpinTouch and block its own UI / the LaMotte app. Also stops
    /// scanning, cancels the connect timeout, and clears connection state.
    private func resetConnectionState() {
        cancelTimeout()
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        dataChar = nil; ackChar = nil; statusChar = nil
        deviceName = nil
        isConnected = false
    }

    /// True if the callback's peripheral is the one we're currently working with.
    private func isCurrent(_ p: CBPeripheral) -> Bool {
        peripheral?.identifier == p.identifier
    }

    private func startTimeout(_ seconds: UInt64, _ message: String) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            switch self.phase {
            case .scanning, .connecting, .discovering, .reading:
                self.addLog("Timed out")
                self.resetConnectionState()
                self.phase = .failed(message)
            default:
                break
            }
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    /// True if this advertisement looks like a SpinTouch.
    private func isSpinTouch(_ peripheral: CBPeripheral, _ adv: [String: Any]) -> Bool {
        let name = (peripheral.name
            ?? (adv[CBAdvertisementDataLocalNameKey] as? String) ?? "")
        if name.localizedCaseInsensitiveContains("spintouch") { return true }
        if let uuids = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           uuids.contains(SpinTouchUUID.service) { return true }
        return false
    }

    private func addLog(_ s: String) {
        let ts = Self.timeFmt.string(from: Date())
        log.append("[\(ts)] \(s)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                addLog("Bluetooth powered on")
                if wantsScan { beginScan() } else if phase == .bluetoothOff { phase = .idle }
            case .poweredOff:
                addLog("Bluetooth powered off")
                phase = .bluetoothOff
            case .unauthorized:
                phase = .failed("Bluetooth permission denied")
            case .unsupported:
                phase = .failed("BLE not supported on this device")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }

            let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = peripheral.name ?? advName ?? "(no name)"

            // Log each distinct device once so we can see what's nearby.
            if seen.insert(peripheral.identifier).inserted {
                addLog("Saw \(name) (RSSI \(RSSI))")
            }

            guard isSpinTouch(peripheral, advertisementData) else { return }

            addLog("Match → connecting to \(name)")
            self.deviceName = peripheral.name ?? advName ?? "SpinTouch"
            self.peripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            phase = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            isConnected = true
            addLog("Connected — discovering services")
            phase = .discovering
            peripheral.discoverServices([SpinTouchUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            resetConnectionState()
            phase = .failed(error?.localizedDescription ?? "Connection failed")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            // Ignore disconnects from a stale peripheral (e.g. an old connection
            // dropping after we've already moved on to a new one).
            guard isCurrent(peripheral) else { return }
            addLog("Disconnected")
            self.peripheral = nil
            self.dataChar = nil; self.ackChar = nil; self.statusChar = nil
            self.isConnected = false
            self.deviceName = nil
            cancelTimeout()
            if case .gotReading = phase {
                // Keep showing results.
            } else if let error {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .idle
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            if let error { resetConnectionState(); phase = .failed(error.localizedDescription); return }
            guard let service = peripheral.services?.first(where: { $0.uuid == SpinTouchUUID.service }) else {
                resetConnectionState()
                phase = .failed("SpinTouch service not found")
                return
            }
            peripheral.discoverCharacteristics(
                [SpinTouchUUID.status, SpinTouchUUID.data, SpinTouchUUID.ack], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            if let error { resetConnectionState(); phase = .failed(error.localizedDescription); return }
            for c in service.characteristics ?? [] {
                switch c.uuid {
                case SpinTouchUUID.status: statusChar = c
                case SpinTouchUUID.data: dataChar = c
                case SpinTouchUUID.ack: ackChar = c
                default: break
                }
            }
            guard let statusChar, let dataChar else {
                resetConnectionState()
                phase = .failed("Required characteristics missing")
                return
            }
            addLog("Subscribing to status notifications")
            peripheral.setNotifyValue(true, for: statusChar)
            // The device only advertises when on a results screen, so a result
            // may already be available — read once immediately.
            phase = .reading
            peripheral.readValue(for: dataChar)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            if let error { addLog("Update error: \(error.localizedDescription)"); return }

            if characteristic.uuid == SpinTouchUUID.status {
                let v = characteristic.value?.first ?? 0
                addLog("Status notification: 0x\(String(format: "%02X", v))")
                // Only kick off one read at a time.
                if phase != .reading, let dataChar {
                    phase = .reading
                    peripheral.readValue(for: dataChar)
                }
                return
            }

            if characteristic.uuid == SpinTouchUUID.data {
                guard let value = characteristic.value else { return }
                addLog("Received \(value.count) bytes")
                if let parsed = SpinTouchParser.parse(value) {
                    cancelTimeout()
                    self.reading = parsed
                    phase = .gotReading
                    addLog("Parsed: \(parsed.summaryLine)")
                    if value.count >= 91 && parsed.endSignatureValid == false {
                        addLog("⚠︎ End signature mismatch (payload may be truncated)")
                    }
                    sendAck()
                    scheduleAutoDisconnect()
                } else {
                    addLog("Payload not a valid test report (\(value.count) bytes)")
                    if phase == .reading {
                        cancelTimeout()
                        phase = .waitingForTest
                    }
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard isCurrent(peripheral) else { return }
            if characteristic.uuid == SpinTouchUUID.status, phase == .reading {
                // remain reading; first read already issued
            } else if characteristic.uuid == SpinTouchUUID.status {
                phase = .waitingForTest
            }
        }
    }

    private func sendAck() {
        guard let peripheral, let ackChar else { return }
        addLog("Sending ACK (0x01)")
        peripheral.writeValue(Data([0x01]), for: ackChar, type: .withResponse)
    }

    /// Disconnect shortly after a reading so the SpinTouch is free for the LaMotte
    /// app / its own UI. The parsed reading stays on screen because the disconnect
    /// handler preserves it while phase == .gotReading.
    private func scheduleAutoDisconnect() {
        autoDisconnectTask?.cancel()
        autoDisconnectTask = Task { @MainActor [weak self] in
            let delay = (self?.autoDisconnectDelaySeconds ?? 8) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, let p = self.peripheral else { return }
            self.addLog("Auto-disconnecting to free the device for the LaMotte app")
            self.central.cancelPeripheralConnection(p)
        }
    }
}

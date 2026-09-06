import Foundation
import Combine
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var lastError: String?
    @Published var lastPacketAt: Date?
    @Published var statusText = "Armband not synced"

    var onReading: ((Reading) -> Void)?

    #if canImport(CoreBluetooth)
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    #endif

    func start() {
        #if canImport(CoreBluetooth)
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            scanIfReady()
        }
        #else
        lastError = "CoreBluetooth not available"
        statusText = "Armband not synced"
        #endif
    }

    func stop() {
        #if canImport(CoreBluetooth)
        isScanning = false
        central?.stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        #endif
        isConnected = false
        statusText = "Armband not synced"
    }

    #if canImport(CoreBluetooth)
    private func scanIfReady() {
        guard let central, central.state == .poweredOn else { return }
        lastError = nil
        isScanning = true
        statusText = "Looking for armband"
        central.scanForPeripherals(withServices: [ArmbandBLE.serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        // Name fallback: some stacks advertise name before service UUID.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.isConnected, self.isScanning else { return }
            self.central?.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    #endif
}

#if canImport(CoreBluetooth)
extension BluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.scanIfReady()
            case .unauthorized:
                self.lastError = "Bluetooth permission denied"
                self.statusText = "Allow Bluetooth in Settings"
                self.isScanning = false
            case .poweredOff:
                self.lastError = "Bluetooth is off"
                self.statusText = "Turn Bluetooth on"
                self.isConnected = false
                self.isScanning = false
            default:
                self.statusText = "Armband not synced"
                self.isScanning = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let match = name == ArmbandBLE.advertisedName || services.contains(ArmbandBLE.serviceUUID)
        guard match else { return }
        Task { @MainActor in
            self.central?.stopScan()
            self.isScanning = false
            self.peripheral = peripheral
            peripheral.delegate = self
            self.statusText = "Connecting to armband"
            self.central?.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.statusText = "Armband connected — waiting for packet"
            peripheral.discoverServices([ArmbandBLE.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Connect failed"
            self.statusText = "Armband not synced"
            self.scanIfReady()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.statusText = "Armband not synced"
            self.scanIfReady()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == ArmbandBLE.serviceUUID }) else {
                return
            }
            peripheral.discoverCharacteristics([ArmbandBLE.jsonCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let char = service.characteristics?.first(where: { $0.uuid == ArmbandBLE.jsonCharUUID }) else {
                return
            }
            peripheral.setNotifyValue(true, for: char)
            peripheral.readValue(for: char)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        let parsed = Reading.fromFirmwareJSON(data)
        Task { @MainActor in
            guard var reading = parsed else { return }
            reading.source = "ble"
            self.lastPacketAt = Date()
            self.statusText = "Armband synced"
            self.onReading?(reading)
        }
    }
}
#endif

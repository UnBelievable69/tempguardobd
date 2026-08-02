import SwiftUI
import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int

    var signal: SignalStrength { SignalStrength(rssi: rssi) }

    var isLikelyOBD: Bool {
        let lower = name.lowercased()
        let keywords = [
            "obd", "elm", "v-link", "vlink", "obdbt", "chx",
            "vgate", "diag", "car", "auto", "scanner", "bt obd"
        ]
        return keywords.contains { lower.contains($0) }
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum SignalStrength {
    case excellent, good, fair, weak

    init(rssi: Int) {
        switch rssi {
        case (-50)...0:       self = .excellent
        case (-70) ..< (-50): self = .good
        case (-85) ..< (-70): self = .fair
        default:              self = .weak
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Отличный"
        case .good:      return "Хороший"
        case .fair:      return "Средний"
        case .weak:      return "Слабый"
        }
    }

    var color: Color {
        switch self {
        case .excellent, .good: return .green
        case .fair:             return .orange
        case .weak:             return .red
        }
    }

    var bars: Int {
        switch self {
        case .excellent: return 4
        case .good:      return 3
        case .fair:      return 2
        case .weak:      return 1
        }
    }
}

final class BluetoothScanner: NSObject, ObservableObject {

    private var centralManager: CBCentralManager!

    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        isScanning = false
    }

    deinit {
        stopScanning()
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Неизвестное устройство"

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }

        discoveredDevices.sort { lhs, rhs in
            if lhs.isLikelyOBD != rhs.isLikelyOBD {
                return lhs.isLikelyOBD
            }
            return lhs.rssi > rhs.rssi
        }
    }
}

import Foundation
import Combine
import CoreBluetooth

final class OBDManager: NSObject, ObservableObject {

    private let settings: SettingsManager

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var isConnected = false

    private var responseBuffer = ""
    private var pendingSent = ""
    private var pendingContinuation: CheckedContinuation<[String], Never>?
    private var connectContinuation: CheckedContinuation<Bool, Never>?
    private var stateContinuation: CheckedContinuation<Void, Never>?
    private var servicesPending = 0
    private var monitoringTask: Task<Void, Never>?

    private let fanOnCommand  = "2F000A06FF"
    private let fanOffCommand = "2F000A00"
    private let coolantTempCommand = "0105"

    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0
    @Published var showError = false
    @Published var errorMessage = ""

    init(settings: SettingsManager) {
        self.settings = settings
        super.init()
    }

    func startConnection() {
        Task { @MainActor in
            monitoringTask?.cancel()
            isConnected = false
            responseBuffer = ""

            guard !settings.selectedDeviceUUID.isEmpty,
                  let uuid = UUID(uuidString: settings.selectedDeviceUUID) else {
                connectionStatus = "Адаптер не выбран"
                errorMessage = "Сначала выберите адаптер: Настройки → Адаптер → нажмите на устройство в списке."
                showError = true
                return
            }

            connectionStatus = "Подключение к " + settings.selectedDeviceName + "..."

            if central == nil {
                central = CBCentralManager(delegate: self, queue: .main)
            }

            if central.state != .poweredOn {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    stateContinuation = cont
                }
            }

            guard central.state == .poweredOn else {
                connectionStatus = "Bluetooth не готов"
                errorMessage = "Включите Bluetooth в Настройках iPhone."
                showError = true
                return
            }

            let list = central.retrievePeripherals(withIdentifiers: [uuid])
            guard let p = list.first else {
                connectionStatus = "Адаптер не найден"
                errorMessage = "Не удалось найти адаптер. Откройте Настройки → Адаптер и выберите его заново."
                showError = true
                return
            }

            peripheral = p
            p.delegate = self

            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                connectContinuation = cont
                central.connect(p, options: nil)
            }

            guard ok else {
                connectionStatus = "Ошибка подключения"
                errorMessage = "Bluetooth соединение не установлено. Убедитесь что адаптер в машине и зажигание включено."
                showError = true
                return
            }

            connectionStatus = "Инициализация адаптера..."
            let _ = await sendCommand("ATZ")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let _ = await sendCommand("ATE0")
            let _ = await sendCommand("ATL0")
            let _ = await sendCommand("ATS0")
            let _ = await sendCommand("ATSP0")
            let _ = await sendCommand("0100")

            connectionStatus = "Подключено. Мониторинг..."
            startTemperatureMonitoring()
        }
    }

    @MainActor
    private func sendCommand(_ cmd: String) async -> [String] {
        guard isConnected, let p = peripheral, let wc = writeChar else { return [] }
        responseBuffer = ""
        pendingSent = cmd.uppercased().replacingOccurrences(of: " ", with: "")
        let data = (cmd + "\r").data(using: .ascii) ?? Data()

        let result: [String] = await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            pendingContinuation = cont
            p.writeValue(data, for: wc, type: writeType)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self = self else { return }
                if let c = self.pendingContinuation {
                    self.pendingContinuation = nil
                    c.resume(returning: self.parseBuffer())
                }
            }
        }
        return result
    }

    private func parseBuffer() -> [String] {
        let raw = responseBuffer
        responseBuffer = ""
        let parts = raw.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        var lines: [String] = []
        for part in parts {
            let line = part.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == ">" { continue }
            let norm = line.uppercased().replacingOccurrences(of: " ", with: "")
            if norm == pendingSent { continue }
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: ">"))
            if trimmed.isEmpty { continue }
            lines.append(trimmed)
        }
        return lines
    }

    private func startTemperatureMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self = self, self.isConnected else { continue }
                let lines = await self.sendCommand(self.coolantTempCommand)
                for line in lines {
                    let n = line.uppercased().replacingOccurrences(of: " ", with: "")
                    if n.hasPrefix("4105") && n.count >= 6 {
                        let hex = String(n.dropFirst(4).prefix(2))
                        if let v = UInt8(hex, radix: 16) {
                            let temperature = Double(v) - 40.0
                            self.currentTemperature = temperature
                            self.evaluateFanLogic(temperature: temperature)
                            break
                        }
                    }
                }
            }
        }
    }

    private func evaluateFanLogic(temperature: Double) {
        let on  = settings.tempTurnOn
        let off = settings.tempTurnOff
        if temperature >= on && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
        } else if temperature <= off && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
        }
    }

    private func executeCommand(_ hexCommand: String, targetState: Bool, statusText: String) {
        Task { @MainActor in
            connectionStatus = statusText
            let _ = await sendCommand(hexCommand)
            isFanCurrentlyOn = targetState
            connectionStatus = targetState ? "Вентилятор ВКЛ" : "Вентилятор ВЫКЛ"
        }
    }

    func stopConnection() {
        monitoringTask?.cancel()
        monitoringTask = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
        connectionStatus = "Отключено"
        isFanCurrentlyOn = false
        currentTemperature = 0.0
    }
}

extension OBDManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if let cont = stateContinuation, c.state != .unknown && c.state != .resetting {
            stateContinuation = nil
            cont.resume()
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: false) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        isConnected = false
        if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: false) }
    }
}

extension OBDManager: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svcs = p.services, !svcs.isEmpty else {
            if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: false) }
            return
        }
        servicesPending = svcs.count
        for s in svcs { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let chars = service.characteristics {
            for ch in chars {
                if writeChar == nil && (ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse)) {
                    writeChar = ch
                    writeType = ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                }
                if notifyChar == nil && ch.properties.contains(.notify) {
                    notifyChar = ch
                }
            }
        }
        servicesPending -= 1
        if servicesPending <= 0 {
            if let nc = notifyChar {
                p.setNotifyValue(true, for: nc)
            } else if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume(returning: false)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == notifyChar {
            isConnected = (error == nil)
            if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: isConnected) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let s = String(data: characteristic.value ?? Data(), encoding: .ascii) else { return }
        guard pendingContinuation != nil else { responseBuffer = ""; return }
        responseBuffer += s
        if responseBuffer.contains(">") {
            if let cont = pendingContinuation {
                pendingContinuation = nil
                cont.resume(returning: parseBuffer())
            }
        }
    }
}

import Foundation
import Combine
import CoreBluetooth

struct TempPoint: Identifiable {
    let id = UUID()
    let time: Date
    let temp: Double
}

struct SessionSummary {
    let duration: TimeInterval
    let maxTemp: Double
    let fanCycles: Int
    let overheats: Int
    let fanOnTime: TimeInterval
}

final class OBDManager: NSObject, ObservableObject {

    private let settings: SettingsManager

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var isConnected = false
    private var connecting = false
    private var manualStop = false
    private var autoRetrying = false
    private var reconnectAttempts = 0
    private var shouldReconnect = false

    private var responseBuffer = ""
    private var pendingSent = ""
    private var pendingContinuation: CheckedContinuation<[String], Never>?
    private var connectContinuation: CheckedContinuation<Bool, Never>?
    private var stateContinuation: CheckedContinuation<Void, Never>?
    private var servicesPending = 0
    private var monitoringTask: Task<Void, Never>?
    private var overheatLogged = false
    private var session = 0
    private var lastReadingTime: Date?

    private var sessionStartTime: Date?
    private var sessionMaxTemp: Double = 0
    private var sessionFanCycles = 0
    private var sessionOverheats = 0
    private var sessionFanOnTime: TimeInterval = 0
    private var fanOnSince: Date?

    private let fanOnCommand  = "2F000A06FF"
    private let fanOffCommand = "2F000A00"
    private let coolantTempCommand = "0105"

    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isMonitoring = false
    @Published var history: [TempPoint] = []
    @Published var fanMode: Int = 0
    @Published var isDataStale = false
    @Published var showSummary = false
    @Published var lastSummary: SessionSummary?

    init(settings: SettingsManager) {
        self.settings = settings
        super.init()
    }

    func dismissSummary() {
        showSummary = false
    }

    func appDidEnterBackground() {
        shouldReconnect = isMonitoring || connecting
    }

    func appWillEnterForeground() {
        if shouldReconnect && !isMonitoring {
            shouldReconnect = false
            startConnection()
        }
    }

    func startConnection(auto: Bool = false) {
        session += 1
        let token = session
        manualStop = false
        if !auto {
            autoRetrying = false
        }

        Task { @MainActor in
            self.monitoringTask?.cancel()
            self.isConnected = false
            self.isMonitoring = false
            self.isDataStale = false
            self.lastReadingTime = nil
            self.responseBuffer = ""

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self else { return }
                if self.session == token && !self.isMonitoring {
                    self.session += 1
                    if self.connecting {
                        self.connecting = false
                        EventJournal.shared.log(5, temp: 0)
                    }
                    self.resetConnectionState()
                    self.connectionStatus = "Тайм-аут подключения"
                    if !self.autoRetrying {
                        self.errorMessage = "Адаптер не ответил за 10 секунд. Убедитесь что зажигание включено и адаптер вставлен в OBD2 разъём."
                        self.showError = true
                    }
                }
            }

            await self.performConnection(token: token)
        }
    }

    private func resetConnectionState() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
        isMonitoring = false
    }

    private func resetSessionTrackers() {
        sessionStartTime = nil
        sessionMaxTemp = 0
        sessionFanCycles = 0
        sessionOverheats = 0
        sessionFanOnTime = 0
        fanOnSince = nil
    }

    private func closeFanOnPeriod() {
        if let s = fanOnSince {
            sessionFanOnTime += Date().timeIntervalSince(s)
            fanOnSince = nil
        }
    }

    @MainActor
    private func performConnection(token: Int) async {
        guard token == session else { return }

        guard !settings.selectedDeviceUUID.isEmpty,
              let uuid = UUID(uuidString: settings.selectedDeviceUUID) else {
            session += 1
            autoRetrying = false
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
        guard token == session else { return }

        guard central.state == .poweredOn else {
            session += 1
            connectionStatus = "Bluetooth не готов"
            if !autoRetrying {
                errorMessage = "Включите Bluetooth в Настройках iPhone."
                showError = true
            }
            return
        }

        let list = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let p = list.first else {
            session += 1
            connectionStatus = "Адаптер не найден"
            if !autoRetrying {
                errorMessage = "Не удалось найти адаптер. Откройте Настройки → Адаптер и выберите его заново."
                showError = true
            }
            attemptReconnect()
            return
        }

        peripheral = p
        p.delegate = self
        connecting = true

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            connectContinuation = cont
            central.connect(p, options: nil)
        }
        guard token == session else { return }

        guard ok else {
            session += 1
            connecting = false
            EventJournal.shared.log(5, temp: 0)
            connectionStatus = "Ошибка подключения"
            if !autoRetrying {
                errorMessage = "Bluetooth соединение не установлено. Убедитесь что адаптер в машине и зажигание включено."
                showError = true
            }
            return
        }

        connectionStatus = "Инициализация адаптера..."
        let _ = await sendCommand("ATZ")
        guard token == session else { return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard token == session else { return }
        let _ = await sendCommand("ATE0")
        let _ = await sendCommand("ATL0")
        let _ = await sendCommand("ATS0")
        let _ = await sendCommand("ATSP0")
        let _ = await sendCommand("0100")
        guard token == session else { return }

        connecting = false
        reconnectAttempts = 0
        autoRetrying = false
        connectionStatus = "Подключено. Мониторинг..."
        isMonitoring = true
        session += 1
        resetSessionTrackers()
        sessionStartTime = Date()
        EventJournal.shared.log(3, temp: 0)
        startTemperatureMonitoring()

        if fanMode == 1 {
            executeCommand(fanOnCommand, targetState: true, statusText: "Принудительно ВКЛ")
            sessionFanCycles += 1
            fanOnSince = Date()
        } else if fanMode == 2 {
            executeCommand(fanOffCommand, targetState: false, statusText: "Принудительно ВЫКЛ")
        }
    }

    func setFanMode(_ mode: Int) {
        let previousMode = fanMode
        fanMode = mode
        guard isConnected else { return }

        if previousMode == 1 && mode != 1 {
            closeFanOnPeriod()
        }

        if mode == 1 {
            executeCommand(fanOnCommand, targetState: true, statusText: "Принудительно ВКЛ")
            if !isFanCurrentlyOn {
                sessionFanCycles += 1
                fanOnSince = Date()
            }
            EventJournal.shared.log(0, temp: currentTemperature)
        } else if mode == 2 {
            executeCommand(fanOffCommand, targetState: false, statusText: "Принудительно ВЫКЛ")
            if isFanCurrentlyOn {
                closeFanOnPeriod()
            }
            EventJournal.shared.log(1, temp: currentTemperature)
        } else {
            connectionStatus = "Подключено. Мониторинг..."
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
                            self.lastReadingTime = Date()
                            self.isDataStale = false
                            self.sessionMaxTemp = Swift.max(self.sessionMaxTemp, temperature)

                            self.history.append(TempPoint(time: Date(), temp: temperature))
                            if self.history.count > 900 {
                                self.history.removeFirst()
                            }

                            if temperature >= 110 && !self.overheatLogged {
                                self.overheatLogged = true
                                self.sessionOverheats += 1
                                EventJournal.shared.log(2, temp: temperature)
                            } else if temperature < 105 {
                                self.overheatLogged = false
                            }

                            self.evaluateFanLogic(temperature: temperature)
                            break
                        }
                    }
                }

                if let t = self.lastReadingTime, Date().timeIntervalSince(t) > 10 {
                    self.isDataStale = true
                }
            }
        }
    }

    private func evaluateFanLogic(temperature: Double) {
        guard fanMode == 0 else { return }
        let on  = settings.tempTurnOn
        let off = settings.tempTurnOff
        if temperature >= on && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
            sessionFanCycles += 1
            fanOnSince = Date()
            EventJournal.shared.log(0, temp: temperature)
        } else if temperature <= off && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
            closeFanOnPeriod()
            EventJournal.shared.log(1, temp: temperature)
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
        session += 1
        manualStop = true
        autoRetrying = false
        connecting = false
        let wasMonitoring = isMonitoring
        monitoringTask?.cancel()
        monitoringTask = nil

        if wasMonitoring {
            closeFanOnPeriod()
            if let start = sessionStartTime, sessionMaxTemp > 0 {
                lastSummary = SessionSummary(
                    duration: Date().timeIntervalSince(start),
                    maxTemp: sessionMaxTemp,
                    fanCycles: sessionFanCycles,
                    overheats: sessionOverheats,
                    fanOnTime: sessionFanOnTime
                )
                showSummary = true
            }
            EventJournal.shared.log(4, temp: 0)
        }

        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isConnected = false
        isMonitoring = false
        isDataStale = false
        connectionStatus = "Отключено"
        isFanCurrentlyOn = false
        currentTemperature = 0.0
        resetSessionTrackers()
    }

    private func attemptReconnect() {
        guard !manualStop && reconnectAttempts < 3 else {
            autoRetrying = false
            return
        }
        reconnectAttempts += 1
        autoRetrying = true
        connectionStatus = "Переподключение..."
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self, !self.isMonitoring, !self.manualStop else { return }
            self.startConnection(auto: true)
        }
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
        if connecting {
            connecting = false
            EventJournal.shared.log(5, temp: 0)
        }
        if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: false) }
        attemptReconnect()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let wasMonitoring = isMonitoring
        isConnected = false
        isMonitoring = false
        isFanCurrentlyOn = false
        monitoringTask?.cancel()

        if wasMonitoring {
            EventJournal.shared.log(4, temp: 0)
        } else if connecting {
            connecting = false
            EventJournal.shared.log(5, temp: 0)
        }

        if let cont = connectContinuation { connectContinuation = nil; cont.resume(returning: false) }

        attemptReconnect()
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

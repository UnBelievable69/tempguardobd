import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

final class OBDManager: ObservableObject {

    private var obdService: OBDService?
    private var monitoringTask: Task<Void, Never>?
    private let settings: SettingsManager

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
    }

    func startConnection() {
        Task { @MainActor in
            do {
                let service = OBDService(connectionType: .bluetooth)
                self.obdService = service

                if let peripheral = retrieveSelectedPeripheral() {
                    connectionStatus = "Подключение к " + settings.selectedDeviceName + "..."
                    try await service.connectToPeripheral(peripheral: peripheral)

                    connectionStatus = "Инициализация адаптера..."
                    try await initializeAdapter(service)
                } else {
                    connectionStatus = "Поиск адаптера ELM327..."
                    let _ = try await service.startConnection(timeout: 15)
                }

                connectionStatus = "Подключено. Мониторинг..."
                startTemperatureMonitoring()

            } catch {
                connectionStatus = "Ошибка: " + error.localizedDescription
                errorMessage = "Не удалось подключиться к ELM327. " + error.localizedDescription
                showError = true
                obdService = nil
            }
        }
    }

    private func retrieveSelectedPeripheral() -> CBPeripheral? {
        guard !settings.selectedDeviceUUID.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: settings.selectedDeviceUUID) else { return nil }
        let central = CBCentralManager(delegate: nil, queue: nil)
        let found = central.retrievePeripherals(withIdentifiers: [uuid])
        return found.first
    }

    private func initializeAdapter(_ service: OBDService) async throws {
        let _ = try await service.sendCommandInternal("ATZ", retries: 3)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let _ = try await service.sendCommandInternal("ATE0", retries: 3)
        let _ = try await service.sendCommandInternal("ATL0", retries: 3)
        let _ = try await service.sendCommandInternal("ATS0", retries: 3)
        let _ = try await service.sendCommandInternal("ATSP0", retries: 3)
        let _ = try? await service.sendCommandInternal("0100", retries: 3)
    }

    private func startTemperatureMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self = self, let service = self.obdService else { break }
                do {
                    let response = try await service.sendCommandInternal(self.coolantTempCommand, retries: 3)
                    for line in response {
                        let cleaned = line.replacingOccurrences(of: " ", with: "")
                        if cleaned.hasPrefix("4105") && cleaned.count >= 6 {
                            let hexString = String(cleaned.dropFirst(4).prefix(2))
                            if let hexValue = UInt8(hexString, radix: 16) {
                                let temperature = Double(hexValue) - 40.0
                                self.currentTemperature = temperature
                                self.evaluateFanLogic(temperature: temperature)
                                break
                            }
                        }
                    }
                } catch {
                    print("Ошибка чтения температуры: " + error.localizedDescription)
                }
            }
        }
    }

    private func evaluateFanLogic(temperature: Double) {
        let turnOnThreshold  = settings.tempTurnOn
        let turnOffThreshold = settings.tempTurnOff
        if temperature >= turnOnThreshold && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
        } else if temperature <= turnOffThreshold && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
        }
    }

    private func executeCommand(_ hexCommand: String, targetState: Bool, statusText: String) {
        Task { @MainActor in
            connectionStatus = statusText
            guard let service = self.obdService else {
                connectionStatus = "Ошибка: сервис не инициализирован"
                return
            }
            do {
                let responseLines: [String] = try await service.sendCommandInternal(hexCommand, retries: 3)
                print("Ответ ЭБУ: " + responseLines.joined(separator: " "))
                isFanCurrentlyOn = targetState
                connectionStatus = targetState ? "Вентилятор ВКЛ" : "Вентилятор ВЫКЛ"
            } catch {
                connectionStatus = "Сбой команды: " + error.localizedDescription
            }
        }
    }

    func stopConnection() {
        monitoringTask?.cancel()
        monitoringTask = nil
        obdService?.stopConnection()
        obdService = nil
        connectionStatus = "Отключено"
        isFanCurrentlyOn = false
        currentTemperature = 0.0
    }
}

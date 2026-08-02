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
            connectionStatus = "Поиск адаптера ELM327..."

            do {
                let service = OBDService(connectionType: .bluetooth)
                self.obdService = service

                let vehicleInfo = try await service.startConnection(timeout: 15)
                let vin = vehicleInfo.vin ?? "авто"
                connectionStatus = "Подключено к " + vin + ". Мониторинг..."
                startTemperatureMonitoring()

            } catch {
                connectionStatus = "Ошибка: " + error.localizedDescription
                errorMessage = "Не удалось подключиться к ELM327. " + error.localizedDescription
                showError = true
                obdService = nil
            }
        }
    }

    private func startTemperatureMonitoring() {
        monitoringTask?.cancel()

        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                guard let self = self, let service = self.obdService else { break }

                do {
                    let results = try await service.requestPIDs(
                        [.mode1(.coolantTemp)],
                        unit: .metric
                    )

                    if let measurement = results[.mode1(.coolantTemp)] {
                        self.currentTemperature = measurement.value
                        self.evaluateFanLogic(temperature: measurement.value)
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
        }
        else if temperature <= turnOffThreshold && isFanCurrentlyOn {
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
                let responseLines: [String] = try await service.sendCommandInternal(
                    hexCommand,
                    retries: 3
                )

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

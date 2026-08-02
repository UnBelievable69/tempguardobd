import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

@MainActor
final class OBDManager: ObservableObject {

    private var obdService: OBDService?
    private var timer: Timer?
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
        connectionStatus = "Поиск адаптера ELM327..."

        Task { @MainActor in
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
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let service = self.obdService else {
                    self?.timer?.invalidate()
                    return
                }

                do {
                    let coolantCommand: OBDCommand = .mode1(.coolantTemp)
                    let result = try await service.sendCommand(coolantCommand)

                    switch result {
                    case .success(let decodeResult):
                        if case .measurementResult(let measurement) = decodeResult {
                            self.currentTemperature = measurement.value
                            self.evaluateFanLogic(temperature: measurement.value)
                        }
                    case .failure(let decodeError):
                        print("Ошибка декодирования: " + String(describing: decodeError))
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
        connectionStatus = statusText

        Task { @MainActor in
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
        timer?.invalidate()
        timer = nil
        obdService?.stopConnection()
        obdService = nil
        connectionStatus = "Отключено"
        isFanCurrentlyOn = false
        currentTemperature = 0.0
    }
}

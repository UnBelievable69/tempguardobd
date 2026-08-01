import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

class OBDManager: ObservableObject {

    // FIX: OBDService создаётся ЛЕНИВО, а не при инициализации.
    // Было: private var obdService = OBDService(connectionType: .bluetooth)
    // Это вызывало CBCentralManager() до запроса разрешения Bluetooth → краш.
    private var obdService: OBDService?

    private var timer: Timer?

    // НАСТРОЙКИ ПОРОГОВ И КОМАНД
    private let tempToTurnOn: Double = 98.0
    private let tempToTurnOff: Double = 90.0

    private let fanOnCommand  = "2F000A06FF"
    private let fanOffCommand = "2F000A00"

    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0

    // MARK: - Подключение

    func startConnection() {
        connectionStatus = "Поиск адаптера..."

        Task {
            do {
                // FIX: создаём OBDService ЗДЕСЬ, когда пользователь нажал кнопку,
                // а не при инициализации View. К этому моменту UI уже загружен
                // и iOS может корректно показать диалог разрешения Bluetooth.
                let service = OBDService(connectionType: .bluetooth)
                self.obdService = service

                let _ = try await service.startConnection()

                await MainActor.run {
                    self.connectionStatus = "Подключено. Мониторинг..."
                    self.startTemperatureMonitoring()
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Ошибка подключения: \(error.localizedDescription)"
                    self.obdService = nil
                }
            }
        }
    }

    // MARK: - Мониторинг температуры

    private func startTemperatureMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let service = self.obdService else { return }

            Task {
                do {
                    let coolantCommand: OBDCommand = .mode1(.coolantTemp)
                    let result = try await service.sendCommand(coolantCommand)

                    await MainActor.run {
                        switch result {
                        case .success(let decodeResult):
                            if case .measurementResult(let measurement) = decodeResult {
                                self.currentTemperature = measurement.value
                                self.evaluateFanLogic(temperature: measurement.value)
                            }
                        case .failure(let error):
                            print("Ошибка декодирования: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    print("Ошибка чтения температуры: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Логика управления вентилятором

    private func evaluateFanLogic(temperature: Double) {
        if temperature >= tempToTurnOn && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
        }
        else if temperature <= tempToTurnOff && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
        }
    }

    // MARK: - Отправка сырой HEX-команды

    private func executeCommand(_ hexCommand: String, targetState: Bool, statusText: String) {
        connectionStatus = statusText

        Task {
            guard let service = self.obdService else {
                await MainActor.run {
                    self.connectionStatus = "Ошибка: сервис не инициализирован"
                }
                return
            }

            do {
                let responseLines: [String] = try await service.sendCommandInternal(
                    hexCommand,
                    retries: 3
                )

                await MainActor.run {
                    print("Ответ ЭБУ на \(hexCommand): \(responseLines.joined(separator: " "))")
                    self.isFanCurrentlyOn = targetState
                    self.connectionStatus = targetState
                        ? "Вентилятор работает (98°C+)"
                        : "Вентилятор отключен (<=90°C)"
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Сбой команды: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Остановка

    func stopConnection() {
        timer?.invalidate()
        timer = nil
        obdService?.stopConnection()
        obdService = nil
        connectionStatus = "Отключено"
        isFanCurrentlyOn = false
    }

    deinit {
        timer?.invalidate()
        obdService?.stopConnection()
    }
}

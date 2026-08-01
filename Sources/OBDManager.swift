import Foundation
import SwiftOBD2
import Combine

class OBDManager: ObservableObject {
    private var obdService = OBDService(connectionType: .bluetooth)
    private var timer: Timer?

    // НАСТРОЙКИ ПОРОГОВ И КОМАНД
    private let tempToTurnOn: Double = 98.0   // Включение при 98°C
    private let tempToTurnOff: Double = 90.0  // Выключение при 90°C

    private let fanOnCommand  = "2F000A06FF"  // Команда принудительного включения
    private let fanOffCommand = "2F000A00"    // Команда возврата контроля ECU

    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0

    // 1. Запуск подключения через async/await API
    func startConnection() {
        connectionStatus = "Поиск адаптера..."

        Task {
            do {
                let _ = try await obdService.startConnection()

                await MainActor.run {
                    self.connectionStatus = "Подключено. Мониторинг..."
                    self.startTemperatureMonitoring()
                }
            } catch {
                await MainActor.run {
                    // FIX: добавлен \ для интерполяции строки
                    self.connectionStatus = "Ошибка подключения: \(error.localizedDescription)"
                }
            }
        }
    }

    // 2. Опрос датчика каждые 2 секунды
    private func startTemperatureMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task {
                do {
                    // FIX: правильный путь к enum — OBDCommand.mode1(.coolantTemp)
                    // Было: OBDCommand.Mode1.coolantTemperature (не существует)
                    let coolantCommand: OBDCommand = .mode1(.coolantTemp)

                    // FIX: sendCommand() возвращает Result<DecodeResult>,
                    // а не объект с .value. Нужно pattern-match.
                    let result = try await self.obdService.sendCommand(coolantCommand)

                    await MainActor.run {
                        switch result {
                        case .success(let decodeResult):
                            // FIX: DecodeResult — enum, извлекаем .measurementResult
                            if case .measurementResult(let measurement) = decodeResult {
                                self.currentTemperature = measurement.value
                                self.evaluateFanLogic(temperature: measurement.value)
                            }
                        case .failure(let error):
                            print("Ошибка декодирования: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    // FIX: добавлен \ для интерполяции строки
                    print("Ошибка чтения температуры: \(error.localizedDescription)")
                }
            }
        }
    }

    // 3. Логика автоматического управления (Гистерезис)
    private func evaluateFanLogic(temperature: Double) {
        if temperature >= tempToTurnOn && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
        }
        else if temperature <= tempToTurnOff && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
        }
    }

    // 4. Отправка сырого HEX-запроса в авто
    private func executeCommand(_ hexCommand: String, targetState: Bool, statusText: String) {
        connectionStatus = statusText

        Task {
            do {
                // FIX: OBDCommand(rawString:) НЕ СУЩЕСТВУЕТ.
                // Для отправки произвольной HEX-команды используем sendCommandInternal(),
                // который возвращает [String] — массив сырых строк ответа.
                let responseLines: [String] = try await obdService.sendCommandInternal(
                    hexCommand,
                    retries: 3
                )

                await MainActor.run {
                    // FIX: responseLines — это [String], а не объект с .rawValue
                    print("Ответ ЭБУ на \(hexCommand): \(responseLines.joined(separator: " "))")
                    self.isFanCurrentlyOn = targetState
                    self.connectionStatus = targetState
                        ? "Вентилятор работает (98°C+)"
                        : "Вентилятор отключен (<=90°C)"
                }
            } catch {
                await MainActor.run {
                    // FIX: добавлен \ для интерполяции строки
                    self.connectionStatus = "Сбой команды: \(error.localizedDescription)"
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
        obdService.stopConnection()
    }
}

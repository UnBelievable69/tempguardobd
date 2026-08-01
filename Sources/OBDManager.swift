import Foundation
import SwiftOBD2
import Combine

class OBDManager: ObservableObject {
    // Согласно актуальной документации класс называется OBDService
    private var obdService = OBDService(connectionType: .bluetooth)
    private var timer: Timer?
    
    // НАСТРОЙКИ ПОРОГОВ И КОМАНД
    private let tempToTurnOn: Double = 98.0   // Включение при 98°C
    private let tempToTurnOff: Double = 90.0  // Выключение при 90°C
    
    private let fanOnCommand = "2F000A06FF"   // Ваша команда принудительного включения
    private let fanOffCommand = "2F000A00"    // Команда возврата контроля ECU
    
    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0

    // 1. Запуск подключения через современный async/await API
    func startConnection() {
        connectionStatus = "Поиск адаптера..."
        
        Task {
            do {
                // Подключение согласно актуальному синтаксису библиотеки
                let _ = try await obdService.startConnection()
                
                await MainActor.run {
                    self.connectionStatus = "Подключено. Мониторинг..."
                    self.startTemperatureMonitoring()
                }
            } catch {
                await MainActor.run {
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
                    // Запрос стандартного Mode 1 PID температуры охлаждающей жидкости
                    let coolantCommand = OBDCommand.Mode1.coolantTemperature
                    let response = try await self.obdService.sendCommand(coolantCommand)
                    
                    await MainActor.run {
                        if let temp = response.value as? Double {
                            self.currentTemperature = temp
                            self.evaluateFanLogic(temperature: temp)
                        }
                    }
                } catch {
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
                // Отправка кастомного диагностического HEX-запроса
                let customCommand = OBDCommand(rawString: hexCommand)
                let response = try await obdService.sendCommand(customCommand)
                
                await MainActor.run {
                    print("Ответ ЭБУ на \(hexCommand): \(response.rawValue)")
                    self.isFanCurrentlyOn = targetState
                    self.connectionStatus = targetState ? "Вентилятор работает (98°C+)" : "Вентилятор отключен (<=90°C)"
                }
            } catch {
                await MainActor.run {
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

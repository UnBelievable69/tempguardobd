import Foundation
import SwiftOBD2
import Combine

class OBDManager: ObservableObject {
    private var obd2Service = OBD2Service()
    private var timer: Timer?
    
    // НАСТРОЙКИ ПОРОГОВ И КОМАНД
    private let tempToTurnOn: Double = 98.0   // Включение при 98°C
    private let tempToTurnOff: Double = 90.0  // Выключение при 90°C
    
    private let fanOnCommand = "2F000A06FF"   // Ваша команда принудительного включения
    private let fanOffCommand = "2F000A00"    // Команда возврата контроля ECU (выключение теста)
    
    // Флаг текущего состояния вентилятора, чтобы не спамить командами в шину
    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0

    // 1. Запуск подключения
    func startConnection() {
        connectionStatus = "Поиск адаптера..."
        
        obd2Service.startConnection(connectionType: .bluetooth) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.connectionStatus = "Подключено. Мониторинг..."
                    self?.startTemperatureMonitoring()
                case .failure(let error):
                    self?.connectionStatus = "Ошибка BLE: \(error.localizedDescription)"
                }
            }
        }
    }

    // 2. Опрос датчика каждые 2 секунды
    private func startTemperatureMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let coolantPid = Command.Mode1.coolantTemperature
            
            self.obd2Service.sendOverOBD(coolantPid) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let obdResponse):
                        if let temp = obdResponse.value as? Double {
                            self.currentTemperature = temp
                            self.evaluateFanLogic(temperature: temp)
                        }
                    case .failure(let error):
                        print("Ошибка чтения PID 05: \(error)")
                    }
                }
            }
        }
    }

    // 3. Логика автоматического управления (Гистерезис)
    private func evaluateFanLogic(temperature: Double) {
        // Условие включения
        if temperature >= tempToTurnOn && !isFanCurrentlyOn {
            executeCommand(fanOnCommand, targetState: true, statusText: "Включение вентилятора...")
        } 
        // Условие выключения
        else if temperature <= tempToTurnOff && isFanCurrentlyOn {
            executeCommand(fanOffCommand, targetState: false, statusText: "Отключение вентилятора...")
        }
    }

    // 4. Отправка сырого HEX-запроса в авто
    private func executeCommand(_ hexCommand: String, targetState: Bool, statusText: String) {
        connectionStatus = statusText
        
        obd2Service.sendRawCommand(hexCommand) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("Ответ ЭБУ на \(hexCommand): \(response)")
                    self?.isFanCurrentlyOn = targetState
                    self?.connectionStatus = targetState ? "Вентилятор работает (98°C+)" : "Вентилятор отключен (<=90°C)"
                case .failure(let error):
                    self?.connectionStatus = "Сбой команды: \(error.localizedDescription)"
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        obd2Service.stopConnection()
    }
}

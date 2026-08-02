import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

// MARK: - Bluetooth Authorization Checker

/// Отдельный класс для проверки разрешения Bluetooth ДО создания OBDService.
/// CBCentralManager создаётся на главном потоке и проверяет статус.
final class BluetoothAuthorizationChecker: NSObject, CBCentralManagerDelegate {

    enum AuthResult {
        case authorized
        case denied
        case notDetermined
        case unsupported
        case poweredOff
    }

    private var centralManager: CBCentralManager!
    private var continuation: CheckedContinuation<AuthResult, Never>?

    /// Проверяет текущий статус Bluetooth.
    /// Если статус ещё не определён — ждёт диалог разрешения (до 10 сек).
    func checkAuthorization() async -> AuthResult {
        // Быстрая проверка без создания CBCentralManager
        switch CBCentralManager.authorization {
        case .allowedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            break // Нужно создать CBCentralManager чтобы показать диалог
        @unknown default:
            return .denied
        }

        // Создаём CBCentralManager на главном потоке чтобы показать диалог
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.async {
                self.centralManager = CBCentralManager(delegate: self, queue: .main)
            }

            // Таймаут 10 секунд на случай если диалог не появился
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.continuation?.resume(returning: .notDetermined)
                self?.continuation = nil
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let result: AuthResult
        switch central.state {
        case .poweredOn:
            result = .authorized
        case .poweredOff:
            result = .poweredOff
        case .unauthorized:
            result = .denied
        case .unsupported:
            result = .unsupported
        default:
            result = .notDetermined
        }

        continuation?.resume(returning: result)
        continuation = nil
    }
}

// MARK: - OBDManager

@MainActor
final class OBDManager: ObservableObject {

    // FIX: OBDService создаётся ЛЕНИВО и ТОЛЬКО на главном потоке.
    // OBDService — это ObservableObject с @Published.
    // Его внутренние обновления приходят из фонового BLE-потока.
    // Если создать его не на MainActor — краш SwiftUI.
    private var obdService: OBDService?

    private var timer: Timer?
    private let authChecker = BluetoothAuthorizationChecker()

    // НАСТРОЙКИ ПОРОГОВ И КОМАНД
    private let tempToTurnOn: Double = 98.0
    private let tempToTurnOff: Double = 90.0

    private let fanOnCommand  = "2F000A06FF"
    private let fanOffCommand = "2F000A00"

    @Published var isFanCurrentlyOn = false
    @Published var connectionStatus = "Отключено"
    @Published var currentTemperature: Double = 0.0
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Подключение

    func startConnection() {
        connectionStatus = "Проверка Bluetooth..."

        Task { @MainActor in
            // ШАГ 1: Проверяем разрешение Bluetooth ДО создания OBDService
            let authResult = await authChecker.checkAuthorization()

            switch authResult {
            case .authorized:
                break // Продолжаем

            case .denied:
                self.connectionStatus = "Bluetooth запрещён. Разрешите в Настройках."
                self.showErrorAlert("Bluetooth доступ запрещён. Откройте Настройки → Конфиденциальность → Bluetooth и разрешите доступ.")
                return

            case .notDetermined:
                self.connectionStatus = "Разрешение Bluetooth не получено."
                self.showErrorAlert("Не удалось получить разрешение Bluetooth. Попробуйте снова.")
                return

            case .unsupported:
                self.connectionStatus = "Bluetooth не поддерживается."
                self.showErrorAlert("Это устройство не поддерживает Bluetooth Low Energy.")
                return

            case .poweredOff:
                self.connectionStatus = "Bluetooth выключен."
                self.showErrorAlert("Включите Bluetooth в Настройках или Пункте управления.")
                return
            }

            // ШАГ 2: Создаём OBDService на ГЛАВНОМ потоке
            self.connectionStatus = "Поиск адаптера ELM327..."

            do {
                let service = OBDService(connectionType: .bluetooth)
                self.obdService = service

                // ШАГ 3: Подключаемся (async — не блокирует UI)
                let vehicleInfo = try await service.startConnection(timeout: 15)

                self.connectionStatus = "Подключено к \(vehicleInfo.vin ?? "авто"). Мониторинг..."
                self.startTemperatureMonitoring()

            } catch {
                self.connectionStatus = "Ошибка: \(error.localizedDescription)"
                self.showErrorAlert("Не удалось подключиться к адаптеру ELM327.\n\nУбедитесь что:\n• Адаптер вставлен в OBD2 разъём\n• Зажигание включено\n• Bluetooth адаптер мигает\n\nОшибка: \(error.localizedDescription)")
                self.obdService = nil
            }
        }
    }

    // MARK: - Мониторинг температуры

    private func startTemperatureMonitoring() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // Timer fires on main RunLoop. Dispatch to MainActor.
            Task { @MainActor [weak self] in
                guard let self = self, let service = self.obdService else {
                    self?.timer?.invalidate()
                    return
                }

                do {
                    let coolantCommand: OBDCommand = .mode1(.coolantTemp)

                    // FIX: sendCommand возвращает кастомный Result из SwiftOBD2
                    // (.success(DecodeResult) / .failure(DecodeError)),
                    // а НЕ встроенный Swift Result<Success, Failure>.
                    let result = try await service.sendCommand(coolantCommand)

                    switch result {
                    case .success(let decodeResult):
                        if case .measurementResult(let measurement) = decodeResult {
                            self.currentTemperature = measurement.value
                            self.evaluateFanLogic(temperature: measurement.value)
                        }

                    case .failure(let decodeError):
                        print("Ошибка декодирования OBD: \(decodeError)")
                    }

                } catch {
                    print("Ошибка чтения температуры: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Логика управления вентилятором (Гистерезис)

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

        Task { @MainActor in
            guard let service = self.obdService else {
                self.connectionStatus = "Ошибка: сервис не инициализирован"
                return
            }

            do {
                // FIX: sendCommandInternal возвращает [String] — массив сырых строк
                let responseLines: [String] = try await service.sendCommandInternal(
                    hexCommand,
                    retries: 3
                )

                print("Ответ ЭБУ на \(hexCommand): \(responseLines.joined(separator: " "))")
                self.isFanCurrentlyOn = targetState
                self.connectionStatus = targetState
                    ? "Вентилятор работает (≥98°C)"
                    : "Вентилятор отключен (≤90°C)"

            } catch {
                self.connectionStatus = "Сбой команды: \(error.localizedDescription)"
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
        currentTemperature = 0.0
    }

    // MARK: - Alert

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}

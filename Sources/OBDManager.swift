import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

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

    func checkAuthorization() async -> AuthResult {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            break
        @unknown default:
            return .denied
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.async {
                self.centralManager = CBCentralManager(delegate: self, queue: .main)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.continuation?.resume(returning: .notDetermined)
                self?.continuation = nil
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let result: AuthResult
        switch central.state {
        case .poweredOn:     result = .authorized
        case .poweredOff:    result = .poweredOff
        case .unauthorized:  result = .denied
        case .unsupported:   result = .unsupported
        default:             result = .notDetermined
        }
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class OBDManager: ObservableObject {

    private var obdService: OBDService?
    private var timer: Timer?
    private let authChecker = BluetoothAuthorizationChecker()
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
        connectionStatus = "Проверка Bluetooth..."

        Task { @MainActor in
            let authResult = await authChecker.checkAuthorization()

            switch authResult {
            case .authorized:
                break
            case .denied:
                connectionStatus = "Bluetooth запрещён."
                showErrorAlert("Bluetooth доступ запрещён. Откройте Настройки → Конфиденциальность → Bluetooth.")
                return
            case .notDetermined:
                connectionStatus = "Разрешение не получено."
                showErrorAlert("Не удалось получить разрешение Bluetooth. Попробуйте снова.")
                return
            case .unsupported:
                connectionStatus = "Bluetooth не поддерживается."
                showErrorAlert("Устройство не поддерживает Bluetooth Low Energy.")
                return
            case .poweredOff:
                connectionStatus = "Bluetooth выключен."
                showErrorAlert("Включите Bluetooth в Настройках.")
                return
            }

            connectionStatus = "Поиск адаптера ELM327..."

            do {
                let service = OBDService(connectionType: .bluetooth)
                self.obdService = service

                let vehicleInfo = try await service.startConnection(timeout: 15)
                connectionStatus = "Подключено к \(vehicleInfo.vin ?? "авто"). Мониторинг..."
                startTemperatureMonitoring()

            } catch {
                connectionStatus = "Ошибка: \(error.localizedDescription)"
                showErrorAlert("Не удалось подключиться к ELM327.\n\nОшибка: \(error.localizedDescription)")
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
                        print("Ошибка декодирования: \(decodeError)")
                    }

                } catch {
                    print("Ошибка чтения температуры: \(error.localizedDescription)")
                }
            }
        }
    }

    private func evaluateFanLogic(temperature: Double) {
        let turnOnThreshold  = settings.tempTurnOn
        let turnOffThreshold = settings.tempTurnOff

        if temperature >= turnOnThreshold && !isFanCurrentlyOn {
            executeCommand(
                fanOnCommand,
                targetState: true,
                statusText: "Включение вентилятора (>=\(Int(turnOnThreshold))°C)..."
            )
        }
        else if temperature <= turnOffThreshold && isFanCurrentlyOn {
            executeCommand(
                fanOffCommand,
                targetState: false,
                statusText: "Отключение вентилятора (<=\(Int(turnOffThreshold))°C)..."
            )
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

                print("Ответ ЭБУ на \(hexCommand): \(responseLines.joined(separator: " "))")
                isFanCurrentlyOn = targetState
                connectionStatus = targetState
                    ? "Вентилятор ВКЛ (>=\(Int(settings.tempTurnOn))°C)"
                    : "Вентилятор ВЫКЛ (<=\(Int(settings.tempTurnOff))°C)"

            } catch {
                connectionStatus = "Сбой команды: \(error.localizedDescription)"
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

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}

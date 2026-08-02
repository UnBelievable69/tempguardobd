import Foundation
import SwiftUI

final class SettingsManager: ObservableObject {

    // MARK: - Keys

    private enum Keys {
        static let tempTurnOn  = "tempTurnOn"
        static let tempTurnOff = "tempTurnOff"
    }

    // MARK: - Limits

    static let minTemp: Double = 70.0
    static let maxTemp: Double = 115.0
    /// Минимальный зазор (гистерезис) между включением и выключением
    static let minGap: Double = 3.0

    // MARK: - Published Properties

    @Published var tempTurnOn: Double {
        didSet {
            tempTurnOn = Self.clamp(tempTurnOn, min: Self.minTemp, max: Self.maxTemp)
            // Если включение опустилось ниже выключения — сдвигаем выключение вниз
            if tempTurnOff >= tempTurnOn - Self.minGap {
                tempTurnOff = tempTurnOn - Self.minGap
            }
            save()
        }
    }

    @Published var tempTurnOff: Double {
        didSet {
            tempTurnOff = Self.clamp(tempTurnOff, min: Self.minTemp, max: Self.maxTemp)
            // Если выключение поднялось выше включения — сдвигаем включение вверх
            if tempTurnOn <= tempTurnOff + Self.minGap {
                tempTurnOn = tempTurnOff + Self.minGap
            }
            save()
        }
    }

    // MARK: - Computed

    /// Разница (гистерезис) между порогами
    var hysteresis: Double {
        tempTurnOn - tempTurnOff
    }

    /// true если настройки корректны
    var isValid: Bool {
        tempTurnOff < tempTurnOn && hysteresis >= Self.minGap
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        // Регистрируем значения по умолчанию
        defaults.register(defaults: [
            Keys.tempTurnOn:  98.0,
            Keys.tempTurnOff: 90.0
        ])

        self.tempTurnOn  = defaults.double(forKey: Keys.tempTurnOn)
        self.tempTurnOff = defaults.double(forKey: Keys.tempTurnOff)

        // Валидация при загрузке
        if tempTurnOff >= tempTurnOn {
            tempTurnOn  = 98.0
            tempTurnOff = 90.0
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(tempTurnOn,  forKey: Keys.tempTurnOn)
        defaults.set(tempTurnOff, forKey: Keys.tempTurnOff)
    }

    /// Сброс к значениям по умолчанию
    func resetToDefaults() {
        tempTurnOn  = 98.0
        tempTurnOff = 90.0
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

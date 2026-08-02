import Foundation
import SwiftUI

final class SettingsManager: ObservableObject {

    // MARK: - Keys

 loop.

---

## ✅ Fixed `Sources/SettingsManager.swift` (complete file)

```swift
import Foundation
import SwiftUI

final class SettingsManager: ObservableObject {

    // MARK: - Keys

    private enum Keys    private enum Keys {
        static let tempTurnOn {
        static let tempTurnOn  = "temp  = "tempTurnOn"
TurnOn"
        static let temp        static let tempTurnOff = "TurnOff = "tempTurnOff"tempTurnOff"
    }


    }

    // MARK:    // MARK: - Limits

    - Limits

    static let minTemp static let minTemp: Double = : Double = 70.070.0
    static let
    static let maxTemp: Double maxTemp: Double = 11 = 115.0
5.0
    /// Минималь    /// Минимальный зазор (ный зазор (гистерезисгистерезис) между включением) между включением и выключением и выключением
    static let
    static let minGap: Double minGap: Double = 3.0 = 3.0

    /// Ф

    /// Флаг защиты от взаимлаг защиты от взаимной рекурсииной рекурсии didSet.
    didSet.
    /// Без него: /// Без него: tempTurnOn.did tempTurnOn.didSet меняет tempSet меняет tempTurnOff → tempTurnOff → tempTurnOff.didSetTurnOff.didSet меняет
    меняет
    /// tempTurnOn /// tempTurnOn → бесконеч → бесконечный циклный цикл → перепол → переполнение стека →нение стека → краш.
 краш.
    private var is    private var isSyncing = falseSyncing = false

    // MARK

    // MARK: - Published Properties: - Published Properties

    @Published

    @Published var tempTurnOn var tempTurnOn: Double {
: Double {
        didSet {
        didSet {
            guard !is            guard !isSyncing else {Syncing else { return }
            return }
            isSyncing = isSyncing = true
            defer true
            defer { isSyncing { isSyncing = false }

 = false }

            var on             var on  = Self.clamp = Self.clamp(tempTurnOn,(tempTurnOn, min: Self.min min: Self.minTemp, max:Temp, max: Self.maxTemp) Self.maxTemp)
            var off
            var off = tempTurnOff = tempTurnOff

            // Вы

            // Выключение должно быть минимумключение должно быть минимум на minGap ниже на minGap ниже включения
            if включения
            if off > on - off > on - Self.minGap { Self.minGap {
                off =
                off = on - Self.min on - Self.minGap
                //Gap
                // Если выключение у Если выключение ушло ниже минимшло ниже минимума — сдвигаума — сдвигаем оба порогаем оба порога вверх
                if вверх
                if off < Self.min off < Self.minTemp {
                   Temp {
                    off = Self.min off = Self.minTemp
                    onTemp
                    on  = off +  = off + Self.minGap
 Self.minGap
                }
                           }
            }

            temp }

            tempTurnOn  =TurnOn  = on
            temp on
            tempTurnOff = offTurnOff = off
            save()
            save()
        }

        }
    }

       }

    @Published var temp @Published var tempTurnOff: DoubleTurnOff: Double {
        didSet {
        didSet {
            guard {
            guard !isSyncing !isSyncing else { return } else { return }
            isSync
            isSyncing = true
ing = true
            defer { is            defer { isSyncing = falseSyncing = false }

            var }

            var off = Self.cl off = Self.clamp(tempTurnOffamp(tempTurnOff, min: Self, min: Self.minTemp, max.minTemp, max: Self.maxTemp: Self.maxTemp)
            var)
            var on  = temp on  = tempTurnOn

           TurnOn

            // Включение должно // Включение должно быть минимум на min быть минимум на minGap выше выключенияGap выше выключения
            if on
            if on < off + Self < off + Self.minGap {
.minGap {
                on = off                on = off + Self.minGap + Self.minGap
                // Если
                // Если включение ушло включение ушло выше максимума выше максимума — сдвигаем — сдвигаем оба порога вниз оба порога вниз
                if on
                if on > Self.maxTemp > Self.maxTemp {
                    on {
                    on  = Self.max  = Self.maxTemp
                    offTemp
                    off = on - Self = on - Self.minGap
               .minGap
                }
            } }
            }

            tempTurn

            tempTurnOff = off
Off = off
            tempTurnOn            tempTurnOn  = on
  = on
            save()
            save()
        }
           }
    }

    // }

    // MARK: - Com MARK: - Computed

    varputed

    var hysteresis hysteresis: Double {
: Double {
        tempTurnOn        tempTurnOn - tempTurnOff - tempTurnOff
    }


    }

    var isValid:    var isValid: Bool {
        Bool {
        tempTurnOff < tempTurnOff < tempTurnOn && tempTurnOn && hysteresis hysteresis >= Self.minGap >= Self.minGap
    }


    }

    // MARK:    // MARK: - Init

    - Init

    init() {
 init() {
        let defaults =        let defaults = UserDefaults.standard
        UserDefaults.standard
        defaults.register(defaults defaults.register(defaults: [
           : [
            Keys.tempTurnOn Keys.tempTurnOn:  9:  98.0,8.0,
            Keys.temp
            Keys.tempTurnOff: TurnOff: 90.090.0
        ])


        ])

        self.tempTurn        self.tempTurnOn  = defaultsOn  = defaults.double(forKey: Keys.double(forKey: Keys.tempTurnOn).tempTurnOn)
        self.temp
        self.tempTurnOff = defaultsTurnOff = defaults.double(forKey: Keys.double(forKey: Keys.tempTurnOff).tempTurnOff)

        // В

        // Валидация приалидация при загрузке — загрузке — под флагом под флагом, чтобы не触发, чтобы не触发 рекур рекурсию
        ifсию
        if tempTurnOff >= tempTurnOff >= tempTurnOn { tempTurnOn {
            isSync
            isSyncing = true
ing = true
            tempTurnOn            tempTurnOn  = 9  = 98.0
8.0
            tempTurnOff            tempTurnOff = 90 = 90.0
            isSyncing = false
            save()
        }
    }

    // MARK: - Actions

    /// Сброс к значениям по умолчанию — один проход, без рекурсии
    func resetToDefaults() {
        isSyncing.0
            isSyncing = false
            save()
        }
    }

    // MARK: - Actions

    /// Сброс к значениям по умолчанию — один проход, без рекурсии
    func resetToDefaults() {
        isSyncing = true
        = true
        tempTurnOn  tempTurnOn  = 98 = 98.0
       .0
        tempTurnOff = tempTurnOff = 90. 90.0
        is0
        isSyncing = falseSyncing = false
        save()
        save()
    }


    }

    // MARK:    // MARK: - Persistence

    - Persistence

    private func save() private func save() {
        let {
        let defaults = UserDefaults.standard defaults = UserDefaults.standard
        defaults.set
        defaults.set(tempTurnOn,(tempTurnOn,  forKey: Keys  forKey: Keys.tempTurnOn).tempTurnOn)
        defaults.set
        defaults.set(tempTurnOff,(tempTurnOff, forKey: Keys.temp forKey: Keys.tempTurnOff)
TurnOff)
    }

       }

    // MARK: - // MARK: - Helpers

    private Helpers

    private static func clamp(_ static func clamp(_ value: Double, value: Double, min: Double, min: Double, max: Double) max: Double) -> Double {
 -> Double {
        Swift.min(S        Swift.min(Swift.max(valuewift.max(value, min), max, min), max)
    })
    }
}

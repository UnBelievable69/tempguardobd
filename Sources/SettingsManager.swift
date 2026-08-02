import Foundation
import SwiftUI

final class SettingsManager: ObservableObject {

    private enum Keys {
        static let tempTurnOn  = "tempTurnOn"
        static let tempTurnOff = "tempTurnOff"
    }

    static let minTemp: Double = 70.0
    static let maxTemp: Double = 115.0
    static let minGap: Double  = 3.0

    private var isSyncing = false

    @Published var tempTurnOn: Double {
        didSet {
            guard !isSyncing else { return }
            isSyncing = true
            defer { isSyncing = false }

            var on  = Self.clamp(tempTurnOn, min: Self.minTemp, max: Self.maxTemp)
            var off = tempTurnOff

            if off > on - Self.minGap {
                off = on - Self.minGap
                if off < Self.minTemp {
                    off = Self.minTemp
                    on  = off + Self.minGap
                }
            }

            tempTurnOn  = on
            tempTurnOff = off
            save()
        }
    }

    @Published var tempTurnOff: Double {
        didSet {
            guard !isSyncing else { return }
            isSyncing = true
            defer { isSyncing = false }

            var off = Self.clamp(tempTurnOff, min: Self.minTemp, max: Self.maxTemp)
            var on  = tempTurnOn

            if on < off + Self.minGap {
                on = off + Self.minGap
                if on > Self.maxTemp {
                    on  = Self.maxTemp
                    off = on - Self.minGap
                }
            }

            tempTurnOff = off
            tempTurnOn  = on
            save()
        }
    }

    var hysteresis: Double {
        tempTurnOn - tempTurnOff
    }

    var isValid: Bool {
        tempTurnOff < tempTurnOn && hysteresis >= Self.minGap
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.tempTurnOn:  98.0,
            Keys.tempTurnOff: 90.0
        ])

        self.tempTurnOn  = defaults.double(forKey: Keys.tempTurnOn)
        self.tempTurnOff = defaults.double(forKey: Keys.tempTurnOff)

        if tempTurnOff >= tempTurnOn {
            isSyncing = true
            tempTurnOn  = 98.0
            tempTurnOff = 90.0
            isSyncing = false
            save()
        }
    }

    func resetToDefaults() {
        isSyncing = true
        tempTurnOn  = 98.0
        tempTurnOff = 90.0
        isSyncing = false
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(tempTurnOn,  forKey: Keys.tempTurnOn)
        defaults.set(tempTurnOff, forKey: Keys.tempTurnOff)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

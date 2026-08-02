import SwiftUI

@main
struct FanControllerApp: App {

    // Общие объекты для всех вкладок
    @StateObject private var settings    = SettingsManager()
    @StateObject private var obdManager: OBDManager

    init() {
        // SettingsManager создаётся первым, OBDManager получает ссылку на него
        let settings = SettingsManager()
        _settings    = StateObject(wrappedValue: settings)
        _obdManager  = StateObject(wrappedValue: OBDManager(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(obdManager: obdManager, settings: settings)
                    .tabItem {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                        Text("Контроллер")
                    }

                SettingsView(settings: settings)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Настройки")
                    }
            }
            .tint(.blue)
        }
    }
}

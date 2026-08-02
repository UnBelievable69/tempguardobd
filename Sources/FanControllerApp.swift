import SwiftUI

@main
struct FanControllerApp: App {

    @StateObject private var settings: SettingsManager
    @StateObject private var obdManager: OBDManager

    init() {
        let s = SettingsManager()
        _settings   = StateObject(wrappedValue: s)
        _obdManager = StateObject(wrappedValue: OBDManager(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(obdManager: obdManager, settings: settings)
                    .tabItem {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                        Text("Контроллер")
                    }

                SettingsView(settings: settings, obdManager: obdManager)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Настройки")
                    }
            }
            .tint(.blue)
        }
    }
}

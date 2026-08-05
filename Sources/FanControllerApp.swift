import SwiftUI

@main
struct FanControllerApp: App {
    @StateObject private var settings = SettingsManager()
    @StateObject private var obdManager: OBDManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let s = SettingsManager()
        _settings = StateObject(wrappedValue: s)
        _obdManager = StateObject(wrappedValue: OBDManager(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(obdManager: obdManager, settings: settings)
                    .tabItem { Label("Контроллер", systemImage: "gauge") }
                SettingsView(settings: settings, obdManager: obdManager)
                    .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if settings.hasSelectedDevice {
                    obdManager.startConnection()
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    obdManager.appDidEnterBackground()
                } else if phase == .active {
                    obdManager.appWillEnterForeground()
                }
            }
        }
    }
}

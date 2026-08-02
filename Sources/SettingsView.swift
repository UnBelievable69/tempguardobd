import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: SettingsManager
    @ObservedObject var obdManager: OBDManager
    @State private var showScanner = false

    var body: some View {
        NavigationView {
            Form {

                Section {
                    Button(action: { showScanner = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Адаптер")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(settings.hasSelectedDevice
                                     ? settings.selectedDeviceName
                                     : "Нажмите для поиска")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if settings.hasSelectedDevice {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(.systemGray3))
                        }
                    }
                } header: {
                    Text("Подключение")
                } footer: {
                    Text("Нажмите для поиска и выбора Bluetooth адаптера ELM327.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "fan.fill")
                                .foregroundColor(.red)
                            Text("Включение вентилятора")
                                .font(.headline)
                            Spacer()
                            Text(String(Int(settings.tempTurnOn)) + "°C")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.red)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settings.tempTurnOn,
                            in: (SettingsManager.minTemp + SettingsManager.minGap)...SettingsManager.maxTemp,
                            step: 1.0
                        )
                        .tint(.red)

                        HStack {
                            Text(String(Int(SettingsManager.minTemp + SettingsManager.minGap)) + "°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(Int(SettingsManager.maxTemp)) + "°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Верхний порог")
                } footer: {
                    Text("Вентилятор включится когда температура ОЖ достигнет этого значения.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "fan")
                                .foregroundColor(.green)
                            Text("Выключение вентилятора")
                                .font(.headline)
                            Spacer()
                            Text(String(Int(settings.tempTurnOff)) + "°C")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.green)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settings.tempTurnOff,
                            in: SettingsManager.minTemp...(SettingsManager.maxTemp - SettingsManager.minGap),
                            step: 1.0
                        )
                        .tint(.green)

                        HStack {
                            Text(String(Int(SettingsManager.minTemp)) + "°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(Int(SettingsManager.maxTemp - SettingsManager.minGap)) + "°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Нижний порог")
                } footer: {
                    Text("Вентилятор выключится когда температура опустится до этого значения. Всегда ниже порога включения.")
                }

                Section {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.orange)
                        Text("Гистерезис (зазор)")
                        Spacer()
                        Text(String(Int(settings.hysteresis)) + "°C")
                            .bold()
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Разница порогов")
                } footer: {
                    Text("Минимальный зазор: " + String(Int(SettingsManager.minGap)) + "°C. Предотвращает частое включение/выключение вентилятора.")
                }

                Section {
                    Button(role: .destructive) {
                        withAnimation {
                            settings.resetToDefaults()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Сбросить пороги (98° / 90°)")
                            Spacer()
                        }
                    }

                    if settings.hasSelectedDevice {
                        Button(role: .destructive) {
                            withAnimation {
                                settings.clearSelectedDevice()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "xmark.circle")
                                Text("Забыть адаптер")
                                Spacer()
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Протокол")
                        Spacer()
                        Text("ELM327 Bluetooth LE")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("О приложении")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showScanner) {
                BluetoothScannerView(settings: settings, isPresented: $showScanner) {
                    obdManager.startConnection()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

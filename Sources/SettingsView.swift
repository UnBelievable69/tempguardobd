import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        NavigationView {
            Form {

                // MARK: - Порог включения
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "fan.fill")
                                .foregroundColor(.red)
                            Text("Включение вентилятора")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(settings.tempTurnOn))°C")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.red)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settings.tempTurnOn,
                            in: SettingsManager.minTemp...SettingsManager.maxTemp,
                            step: 1.0
                        )
                        .tint(.red)

                        HStack {
                            Text("\(Int(SettingsManager.minTemp))°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(SettingsManager.maxTemp))°")
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

                // MARK: - Порог выключения
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "fan")
                                .foregroundColor(.green)
                            Text("Выключение вентилятора")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(settings.tempTurnOff))°C")
                                .font(.title2)
                                .bold()
                                .foregroundColor(.green)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settings.tempTurnOff,
                            in: SettingsManager.minTemp...SettingsManager.maxTemp,
                            step: 1.0
                        )
                        .tint(.green)

                        HStack {
                            Text("\(Int(SettingsManager.minTemp))°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(SettingsManager.maxTemp))°")
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

                // MARK: - Гистерезис
                Section {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.orange)
                        Text("Гистерезис (зазор)")
                        Spacer()
                        Text("\(Int(settings.hysteresis))°C")
                            .bold()
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }

                    // Визуальная шкала
                    HysteresisBar(
                        tempOff: settings.tempTurnOff,
                        tempOn: settings.tempTurnOn,
                        minTemp: SettingsManager.minTemp,
                        maxTemp: SettingsManager.maxTemp
                    )
                    .frame(height: 30)
                    .padding(.vertical, 4)

                } header: {
                    Text("Разница порогов")
                } footer: {
                    Text("Минимальный зазор: \(Int(SettingsManager.minGap))°C. Предотвращает частое включение/выключение вентилятора.")
                }

                // MARK: - Сброс
                Section {
                    Button(role: .destructive) {
                        withAnimation {
                            settings.resetToDefaults()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Сбросить по умолчанию (98° / 90°)")
                            Spacer()
                        }
                    }
                }

                // MARK: - Информация
                Section {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Адаптер")
                        Spacer()
                        Text("ELM327 Bluetooth")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("О приложении")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Визуальная шкала гистерезиса

struct HysteresisBar: View {
    let tempOff: Double
    let tempOn: Double
    let minTemp: Double
    let maxTemp: Double

    var body: some View {
        GeometryReader { geo in
            let totalRange = maxTemp - minTemp
            let offFraction = (tempOff - minTemp) / totalRange
            let onFraction  = (tempOn  - minTemp) / totalRange

            ZStack(alignment: .leading) {

                // Фон
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(height: 12)

                // Зона между порогами (гистерезис)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.5), .orange.opacity(0.5), .red.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(geo.size.width * (onFraction - offFraction), 8),
                        height: 12
                    )
                    .offset(x: geo.size.width * offFraction)

                // Маркер выключения
                Circle()
                    .fill(Color.green)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("\(Int(tempOff))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: geo.size.width * offFraction - 9)

                // Маркер включения
                Circle()
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("\(Int(tempOn))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: geo.size.width * onFraction - 9)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsManager())
    }
}

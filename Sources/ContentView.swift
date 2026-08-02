import SwiftUI

struct ContentView: View {
    @ObservedObject var obdManager: OBDManager
    @ObservedObject var settings: SettingsManager

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {

                if settings.displayMode == 1 {
                    TemperatureGraphView(obdManager: obdManager, settings: settings)
                } else if settings.displayMode == 2 {
                    FanOverrideView(obdManager: obdManager)
                } else if settings.displayMode == 3 {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            TemperatureGraphView(obdManager: obdManager, settings: settings)
                            compactControls
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    classicView
                }

                Spacer()

                if obdManager.isMonitoring {
                    Button(action: { obdManager.stopConnection() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Отключить")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: { obdManager.startConnection() }) {
                        Text("Подключиться к ELM327")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Text(obdManager.connectionStatus)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Контроллер")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .alert("Ошибка", isPresented: $obdManager.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(obdManager.errorMessage)
        }
    }

    private var compactControls: some View {
        VStack(spacing: 12) {

            HStack(spacing: 6) {
                Circle()
                    .fill(obdManager.isFanCurrentlyOn ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
                Text(fanStatusText)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            HStack(spacing: 0) {
                segmentButton("АВТО", 0)
                segmentButton("ВКЛ", 1)
                segmentButton("ВЫКЛ", 2)
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)

            HStack(spacing: 20) {
                ThresholdBadge(label: "ВКЛ", temp: settings.tempTurnOn, color: .red, icon: "fan.fill", showLabel: false)
                ThresholdBadge(label: "ВЫКЛ", temp: settings.tempTurnOff, color: .green, icon: "fan", showLabel: false)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    private var fanStatusText: String {
        if obdManager.fanMode == 1 { return "Вентилятор: ВКЛ" }
        if obdManager.fanMode == 2 { return "Вентилятор: ВЫКЛ" }
        return obdManager.isFanCurrentlyOn ? "Вентилятор: ВКЛ" : "Вентилятор: АВТО (ВЫКЛ)"
    }

    private func segmentButton(_ title: String, _ mode: Int) -> some View {
        Button(action: { obdManager.setFanMode(mode) }) {
            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundColor(obdManager.fanMode == mode ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(obdManager.fanMode == mode ? segmentColor(mode) : Color.clear)
                .cornerRadius(12)
        }
    }

    private func segmentColor(_ mode: Int) -> Color {
        if mode == 1 { return .red }
        if mode == 2 { return .green }
        return .blue
    }

    private var classicView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(String(Int(obdManager.currentTemperature)) + "°C")
                    .font(.system(size: 74, weight: .bold, design: .rounded))
                    .foregroundColor(temperatureColor)
                    .monospacedDigit()
                Text("Температура ОЖ")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top, 20)

            HStack(spacing: 20) {
                ThresholdBadge(label: "ВКЛ", temp: settings.tempTurnOn, color: .red, icon: "fan.fill")
                ThresholdBadge(label: "ВЫКЛ", temp: settings.tempTurnOff, color: .green, icon: "fan")
            }

            HStack {
                Circle()
                    .fill(obdManager.isFanCurrentlyOn ? Color.red : Color.green)
                    .frame(width: 15, height: 15)
                Text(obdManager.isFanCurrentlyOn ? "Вентилятор: ВКЛ" : "Вентилятор: АВТО (ВЫКЛ)")
                    .font(.headline)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var temperatureColor: Color {
        if obdManager.currentTemperature >= settings.tempTurnOn  { return .red }
        if obdManager.currentTemperature >= settings.tempTurnOff { return .orange }
        return .blue
    }
}

struct ThresholdBadge: View {
    let label: String
    let temp: Double
    let color: Color
    let icon: String
    var showLabel: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(String(Int(temp)) + "°C")
                .font(.title3)
                .bold()
                .foregroundColor(color)
                .monospacedDigit()
            if showLabel {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 90)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

import SwiftUI

struct ContentView: View {
    @ObservedObject var obdManager: OBDManager
    @ObservedObject var settings: SettingsManager

    var body: some View {
        NavigationView {
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

                Spacer()

                Button(action: { obdManager.startConnection() }) {
                    Text(obdManager.isMonitoring ? "Мониторинг активен" : "Подключиться к ELM327")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(obdManager.isMonitoring ? Color.green : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(obdManager.isMonitoring)
                .padding(.horizontal)

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

    private var temperatureColor: Color {
        if obdManager.currentTemperature >= settings.tempTurnOn { return .red }
        if obdManager.currentTemperature >= settings.tempTurnOff { return .orange }
        return .blue
    }
}

struct ThresholdBadge: View {
    let label: String
    let temp: Double
    let color: Color
    let icon: String

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
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 90)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

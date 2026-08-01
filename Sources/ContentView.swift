import SwiftUI

struct ContentView: View {
    @StateObject private var obdManager = OBDManager()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("OBD2 Контроллер Вентилятора")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.top)
            
            VStack {
                Text("\(Int(obdManager.currentTemperature))°C")
                    .font(.system(size: 74, weight: .bold, design: .rounded))
                    .foregroundColor(temperatureColor)
                Text("Температура ОЖ")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding()
            
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
            
            Button(action: {
                obdManager.startConnection()
            }) {
                Text(obdManager.connectionStatus.contains("Подключено") ? "Мониторинг активен" : "Подключиться к ELM327")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(obdManager.connectionStatus.contains("Подключено") ? Color.green : Color.blue)
                    .cornerRadius(12)
            }
            .disabled(obdManager.connectionStatus.contains("Подключено"))
            .padding(.horizontal)
            
            Text(obdManager.connectionStatus)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private var temperatureColor: Color {
        if obdManager.currentTemperature >= 98 { return .red }
        if obdManager.currentTemperature >= 90 { return .orange }
        return .blue
    }
}

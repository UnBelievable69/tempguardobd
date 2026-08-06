import SwiftUI

struct FanOverrideView: View {

    @ObservedObject var obdManager: OBDManager
    @State private var angle: Double = 0

    private let spinTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {

            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 12)

                Circle()
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .shadow(color: ringColor.opacity(0.8), radius: 14)

                Image(systemName: "fan.fill")
                    .font(.system(size: 110))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 230, height: 230)
            .onReceive(spinTimer) { _ in
                if obdManager.isFanCurrentlyOn {
                    angle = (angle + 8).truncatingRemainder(dividingBy: 360)
                }
            }

            Text(modeTitle)
                .font(.title3)
                .bold()
                .foregroundColor(ringColor)

            Text(String(Int(obdManager.currentTemperature)) + "°C")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .monospacedDigit()

            HStack(spacing: 10) {
                modeButton("АВТО", 0)
                modeButton("ВКЛ", 1)
                modeButton("ВЫКЛ", 2)
            }
            .padding(.horizontal)

            Text("В режиме АВТО вентилятор управляется по температуре. ВКЛ и ВЫКЛ — принудительное управление.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private var ringColor: Color {
        if !obdManager.isMonitoring { return .gray }
        if obdManager.fanMode == 1 { return .red }
        if obdManager.fanMode == 2 { return .green }
        return obdManager.isFanCurrentlyOn ? .orange : .blue
    }

    private var modeTitle: String {
        if !obdManager.isMonitoring { return "НЕТ ПОДКЛЮЧЕНИЯ" }
        if obdManager.fanMode == 1 { return "ПРИНУДИТЕЛЬНО ВКЛ" }
        if obdManager.fanMode == 2 { return "ПРИНУДИТЕЛЬНО ВЫКЛ" }
        return "АВТОМАТИЧЕСКИЙ РЕЖИМ"
    }

    private func modeButton(_ title: String, _ mode: Int) -> some View {
        Button(action: { obdManager.setFanMode(mode) }) {
            Text(title)
                .font(.headline)
                .foregroundColor(obdManager.fanMode == mode ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(obdManager.fanMode == mode ? colorFor(mode) : Color(.systemGray6))
                .cornerRadius(12)
        }
    }

    private func colorFor(_ mode: Int) -> Color {
        if mode == 1 { return .red }
        if mode == 2 { return .green }
        return .blue
    }
}

import SwiftUI

struct TempPoint: Identifiable {
    let id = UUID()
    let time: Date
    let temp: Double
}

struct TemperatureGraphView: View {

    @ObservedObject var obdManager: OBDManager
    @ObservedObject var settings: SettingsManager

    private let minT: Double = 60
    private let maxT: Double = 120
    private let maxPoints = 150

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            Text(String(Int(obdManager.currentTemperature)) + "°C")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(tempColor)
                .monospacedDigit()

            if obdManager.history.count > 1 {
                chart

                HStack {
                    if let firstTime = slice.first?.time {
                        Text(Self.timeFormatter.string(from: firstTime))
                    }
                    Spacer()
                    Text("сейчас")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Нет данных")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Подключитесь к адаптеру — график появится автоматически")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            }
        }
        .padding(.horizontal)
    }

    private var tempColor: Color {
        if obdManager.currentTemperature >= settings.tempTurnOn { return .red }
        if obdManager.currentTemperature >= settings.tempTurnOff { return .orange }
        return .blue
    }

    private var slice: [TempPoint] {
        let pts = obdManager.history
        if pts.count <= maxPoints { return pts }
        return Array(pts[(pts.count - maxPoints)...])
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {

                areaPath(w: w, h: h)
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.45), .blue.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                thresholdLine(temp: settings.tempTurnOn, color: .red, w: w, h: h,
                              label: "ВКЛ " + String(Int(settings.tempTurnOn)) + "°")

                thresholdLine(temp: settings.tempTurnOff, color: .green, w: w, h: h,
                              label: "ВЫКЛ " + String(Int(settings.tempTurnOff)) + "°")

                curvePath(w: w, h: h)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: .orange.opacity(0.7), radius: 6)

                lastDot(w: w, h: h)
            }
        }
        .frame(height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }

    private func yFor(_ temp: Double, h: CGFloat) -> CGFloat {
        let frac = (temp - minT) / (maxT - minT)
        let clamped = min(max(frac, 0), 1)
        return h - CGFloat(clamped) * h
    }

    private func pointAt(_ i: Int, pts: [TempPoint], w: CGFloat, h: CGFloat) -> CGPoint {
        let x = CGFloat(i) / CGFloat(max(pts.count - 1, 1)) * w
        return CGPoint(x: x, y: yFor(pts[i].temp, h: h))
    }

    private func curvePath(w: CGFloat, h: CGFloat) -> Path {
        var path = Path()
        let pts = slice
        guard pts.count > 1 else { return path }
        for i in 0..<pts.count {
            let pt = pointAt(i, pts: pts, w: w, h: h)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }

    private func areaPath(w: CGFloat, h: CGFloat) -> Path {
        let pts = slice
        guard pts.count > 1 else { return Path() }
        var path = curvePath(w: w, h: h)
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }

    private func thresholdLine(temp: Double, color: Color, w: CGFloat, h: CGFloat, label: String) -> some View {
        let y = yFor(temp, h: h)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
            }
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 4)
                .offset(x: w - 74, y: max(y - 16, 0))
        }
    }

    private func lastDot(w: CGFloat, h: CGFloat) -> some View {
        Group {
            if !slice.isEmpty {
                let pt = pointAt(slice.count - 1, pts: slice, w: w, h: h)
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .orange, radius: 6)
                    .offset(x: pt.x - 5, y: pt.y - 5)
            }
        }
    }
}

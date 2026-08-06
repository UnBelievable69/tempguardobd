import SwiftUI

struct TemperatureGraphView: View {

    @ObservedObject var obdManager: OBDManager
    @ObservedObject var settings: SettingsManager
    @ObservedObject var journal = EventJournal.shared

    @State private var rangeMinutes = 10
    @State private var scrubTime: Date? = nil

    private let minT: Double = 60
    private let maxT: Double = 120

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
                .opacity(obdManager.isDataStale ? 0.35 : 1)

            if obdManager.isDataStale {
                Text("Нет свежих данных")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            rangeSelector

            if slice.count > 1 {
                chart

                HStack {
                    if let first = slice.first {
                        Text(Self.timeFormatter.string(from: first.time))
                    }
                    Spacer()
                    Text("сейчас")
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                Text("Тяни по графику для просмотра, двойной тап — сброс")
                    .font(.system(size: 9))
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
        if obdManager.currentTemperature >= settings.tempTurnOn  { return .red }
        if obdManager.currentTemperature >= settings.tempTurnOff { return .orange }
        return .blue
    }

    private var rangeSelector: some View {
        HStack(spacing: 0) {
            rangeButton(5)
            rangeButton(10)
            rangeButton(30)
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .frame(maxWidth: 240)
    }

    private func rangeButton(_ minutes: Int) -> some View {
        Button(action: {
            rangeMinutes = minutes
            scrubTime = nil
        }) {
            Text(String(minutes) + " мин")
                .font(.caption)
                .bold()
                .foregroundColor(rangeMinutes == minutes ? .white : .secondary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(rangeMinutes == minutes ? Color.blue : Color.clear)
                .cornerRadius(10)
        }
    }

    private var slice: [TempPoint] {
        let cutoff = Date().addingTimeInterval(-Double(rangeMinutes) * 60)
        return obdManager.history.filter { $0.time >= cutoff }
    }

    private var t0: Date { slice.first?.time ?? Date() }
    private var t1: Date { slice.last?.time ?? Date() }
    private var span: TimeInterval { max(t1.timeIntervalSince(t0), 1) }

    private var visibleEvents: [LogEvent] {
        journal.events.filter {
            ($0.type == 0 || $0.type == 1 || $0.type == 2) &&
            $0.time >= t0 && $0.time <= t1
        }
    }

    private func xFor(_ time: Date, w: CGFloat) -> CGFloat {
        CGFloat(time.timeIntervalSince(t0) / span) * w
    }

    private func timeAt(x: CGFloat, w: CGFloat) -> Date {
        let frac = Double(min(max(x / w, 0), 1))
        return t0.addingTimeInterval(frac * span)
    }

    private func yFor(_ temp: Double, h: CGFloat) -> CGFloat {
        let frac = (temp - minT) / (maxT - minT)
        let clamped = min(max(frac, 0), 1)
        return h - CGFloat(clamped) * h
    }

    private func pointAt(_ i: Int, pts: [TempPoint], w: CGFloat, h: CGFloat) -> CGPoint {
        CGPoint(x: xFor(pts[i].time, w: w), y: yFor(pts[i].temp, h: h))
    }

    private func nearestPoint(to time: Date) -> TempPoint? {
        slice.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) })
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

                eventDots(w: w, h: h)

                lastDot(w: w, h: h)

                scrubOverlay(w: w, h: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        scrubTime = timeAt(x: value.location.x, w: w)
                    }
            )
            .onTapGesture(count: 2) { scrubTime = nil }
        }
        .frame(height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
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

    private func eventDots(w: CGFloat, h: CGFloat) -> some View {
        ForEach(visibleEvents) { event in
            Circle()
                .fill(colorFor(event.type))
                .frame(width: 8, height: 8)
                .offset(x: xFor(event.time, w: w) - 4, y: yFor(event.temp, h: h) - 4)
        }
    }

    private func colorFor(_ type: Int) -> Color {
        switch type {
        case 0: return .red
        case 1: return .green
        case 2: return .orange
        default: return .gray
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

    private func scrubOverlay(w: CGFloat, h: CGFloat) -> some View {
        Group {
            if let st = scrubTime, let pt = nearestPoint(to: st) {
                let x = xFor(pt.time, w: w)
                let y = yFor(pt.temp, h: h)

                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 1)

                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .offset(x: x - 7, y: y - 7)

                Text(Self.timeFormatter.string(from: pt.time) + " · " + String(Int(pt.temp)) + "°")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .offset(x: min(max(x - 45, 0), w - 90), y: 0)
            }
        }
    }
}

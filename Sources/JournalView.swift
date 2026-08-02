import SwiftUI

struct JournalView: View {

    @ObservedObject var journal = EventJournal.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        List {
            if journal.events.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("Журнал пуст")
                            .foregroundColor(.secondary)
                        Text("События появятся после подключения к адаптеру")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section(header: Text("События")) {
                    ForEach(journal.events) { event in
                        EventRow(event: event, formatter: Self.timeFormatter)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        journal.clear()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Очистить журнал")
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Журнал событий")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EventRow: View {
    let event: LogEvent
    let formatter: DateFormatter

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(formatter.string(from: event.time))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if showsTemp {
                Text(String(Int(event.temp)) + "°C")
                    .font(.headline)
                    .foregroundColor(iconColor)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch event.type {
        case 0: return "fan.fill"
        case 1: return "fan.fill"
        case 2: return "exclamationmark.triangle.fill"
        case 3: return "bolt.fill"
        case 5: return "xmark.circle.fill"
        default: return "slash.circle"
        }
    }

    private var iconColor: Color {
        switch event.type {
        case 0: return .red
        case 1: return .green
        case 2: return .orange
        case 3: return .blue
        case 5: return .red
        default: return .gray
        }
    }

    private var showsTemp: Bool {
        event.type == 0 || event.type == 1 || event.type == 2
    }

    private var title: String {
        switch event.type {
        case 0: return "Вентилятор ВКЛ"
        case 1: return "Вентилятор ВЫКЛ"
        case 2: return "Перегрев!"
        case 3: return "Подключено к ELM327"
        case 5: return "Не удалось подключиться"
        default: return "Отключено"
        }
    }
}

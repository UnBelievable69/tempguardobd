import Foundation
import Combine

struct LogEvent: Codable, Identifiable {
    let id: UUID
    let time: Date
    let type: Int
    let temp: Double
}

final class EventJournal: ObservableObject {

    static let shared = EventJournal()

    @Published var events: [LogEvent] = []

    private let storageKey = "eventJournalData"
    private let maxEvents = 200

    init() {
        load()
    }

    func log(_ type: Int, temp: Double) {
        let event = LogEvent(id: UUID(), time: Date(), type: type, temp: temp)
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast()
        }
        save()
    }

    func clear() {
        events.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let loaded = try? JSONDecoder().decode([LogEvent].self, from: data) {
            events = loaded
        }
    }
}

import Foundation
import UserNotifications

final class DeviceRepository {
    private let store: JSONFileStore<[NetworkDevice]>

    init() {
        store = JSONFileStore(fileName: "devices.json", fallback: [])
    }

    func load() -> [NetworkDevice] { store.load() }
    func save(_ devices: [NetworkDevice]) { store.save(devices) }
    func clear() { store.save([]) }
}

final class ActivityRepository {
    private let store: JSONFileStore<[ActivityItem]>

    init() {
        store = JSONFileStore(fileName: "activity.json", fallback: [])
    }

    func load() -> [ActivityItem] { store.load().sorted { $0.date > $1.date } }
    func save(_ events: [ActivityItem]) { store.save(Array(events.prefix(2_000))) }
    func clear() { store.save([]) }
}

private final class JSONFileStore<Value: Codable> {
    private let url: URL
    private let fallback: Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String, fallback: Value) {
        self.fallback = fallback
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Loom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(fileName)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> Value {
        guard let data = try? Data(contentsOf: url),
              let value = try? decoder.decode(Value.self, from: data) else { return fallback }
        return value
    }

    func save(_ value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var scanAutomatically: Bool { didSet { save(scanAutomatically, "scanAutomatically") } }
    @Published var backgroundMonitoring: Bool { didSet { save(backgroundMonitoring, "backgroundMonitoring") } }
    @Published var notifyNewDevice: Bool { didSet { save(notifyNewDevice, "notifyNewDevice") } }
    @Published var automaticDiscovery: Bool { didSet { save(automaticDiscovery, "automaticDiscovery") } }
    @Published var bonjourDiscovery: Bool { didSet { save(bonjourDiscovery, "bonjourDiscovery") } }
    @Published var activeSubnetDiscovery: Bool { didSet { save(activeSubnetDiscovery, "activeSubnetDiscovery") } }
    @Published var periodicRescanSeconds: Double { didSet { save(periodicRescanSeconds, "periodicRescanSeconds") } }
    @Published var serviceDiscovery: Bool { didSet { save(serviceDiscovery, "serviceDiscovery") } }
    @Published var commonServiceChecks: Bool { didSet { save(commonServiceChecks, "commonServiceChecks") } }
    @Published var notifyDeviceReturned: Bool { didSet { save(notifyDeviceReturned, "notifyDeviceReturned") } }
    @Published var notifyImportantChanges: Bool { didSet { save(notifyImportantChanges, "notifyImportantChanges") } }

    init() {
        scanAutomatically = Self.read(defaults, "scanAutomatically", fallback: true)
        backgroundMonitoring = Self.read(defaults, "backgroundMonitoring", fallback: true)
        notifyNewDevice = Self.read(defaults, "notifyNewDevice", fallback: false)
        automaticDiscovery = Self.read(defaults, "automaticDiscovery", fallback: true)
        bonjourDiscovery = Self.read(defaults, "bonjourDiscovery", fallback: true)
        activeSubnetDiscovery = Self.read(defaults, "activeSubnetDiscovery", fallback: true)
        periodicRescanSeconds = Self.read(defaults, "periodicRescanSeconds", fallback: 300)
        serviceDiscovery = Self.read(defaults, "serviceDiscovery", fallback: true)
        commonServiceChecks = Self.read(defaults, "commonServiceChecks", fallback: true)
        notifyDeviceReturned = Self.read(defaults, "notifyDeviceReturned", fallback: false)
        notifyImportantChanges = Self.read(defaults, "notifyImportantChanges", fallback: false)
    }

    func requestNotificationPermissionIfNeeded() {
        guard notifyNewDevice || notifyDeviceReturned || notifyImportantChanges else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private static func read<T>(_ defaults: UserDefaults, _ key: String, fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }
}

enum LocalNotificationService {
    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

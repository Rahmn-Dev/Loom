import Foundation
import SwiftUI

enum DeviceKind: String, Codable, CaseIterable {
    case computer, laptop, desktop, phone, tablet, television, speaker, printer, router, smartHome
    case gameConsole, nasServer, wearable, unknown

    var symbol: String {
        switch self {
        case .computer, .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .television: "tv"
        case .speaker: "homepodmini"
        case .printer: "printer"
        case .router: "wifi.router"
        case .smartHome: "lightbulb.led"
        case .gameConsole: "gamecontroller"
        case .nasServer: "externaldrive.connected.to.line.below"
        case .wearable: "applewatch"
        case .unknown: "network"
        }
    }

    var tint: Color {
        switch self {
        case .router: .cyan
        case .unknown: .orange
        case .phone, .tablet, .wearable: Color(red: 0.30, green: 0.75, blue: 1)
        case .smartHome: .yellow
        default: Color(red: 0.49, green: 0.58, blue: 1)
        }
    }

    var categoryLabel: String {
        switch self {
        case .computer: "Computer"
        case .laptop: "Laptop"
        case .desktop: "Desktop"
        case .phone: "Phone"
        case .tablet: "Tablet"
        case .television: "Television"
        case .speaker: "Speaker / Audio"
        case .printer: "Printer"
        case .router: "Router / Network Device"
        case .smartHome: "Smart Home / IoT"
        case .gameConsole: "Game Console"
        case .nasServer: "NAS / Server"
        case .wearable: "Wearable"
        case .unknown: "Other / Unknown"
        }
    }

    static let customizationOptions: [DeviceKind] = [
        .phone, .tablet, .laptop, .desktop, .television, .gameConsole, .router,
        .smartHome, .printer, .nasServer, .wearable, .unknown
    ]
}

enum ServiceEvidence: String, Codable, CaseIterable {
    case discovered
    case open

    var label: String { rawValue.uppercased() }
}

struct NetworkServiceObservation: Identifiable, Codable, Hashable {
    var id: String { "\(name.lowercased())-\(port ?? 0)-\(evidence.rawValue)" }
    var name: String
    var type: String?
    var port: UInt16?
    var evidence: ServiceEvidence
    var firstSeen: Date
    var lastSeen: Date

    init(name: String, type: String? = nil, port: UInt16? = nil,
         evidence: ServiceEvidence, firstSeen: Date = .now, lastSeen: Date = .now) {
        self.name = name
        self.type = type
        self.port = port
        self.evidence = evidence
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

struct NetworkDevice: Identifiable, Equatable, Codable {
    var id: String
    /// Name observed from hostname, Bonjour, or another discovery source.
    var name: String
    /// User-owned label. Kept separate so later discovery never overwrites it.
    var customName: String?
    var ipAddress: String
    var macAddress: String?
    var vendor: String?
    var hostname: String?
    /// Automatically detected category. Never overwritten by user customization.
    var kind: DeviceKind
    var customKind: DeviceKind?
    var services: Set<String>
    var serviceObservations: [NetworkServiceObservation]
    var latencyMS: Int?
    var firstSeen: Date
    var lastSeen: Date
    var isOnline: Bool
    var isNew: Bool
    var isTrusted: Bool
    var isLocal: Bool
    var isGateway: Bool

    init(id: String = UUID().uuidString, name: String, customName: String? = nil,
         ipAddress: String, macAddress: String? = nil,
         vendor: String? = nil, hostname: String? = nil, kind: DeviceKind = .unknown,
         customKind: DeviceKind? = nil,
         services: Set<String> = [], serviceObservations: [NetworkServiceObservation] = [],
         latencyMS: Int? = nil, firstSeen: Date = .now, lastSeen: Date = .now,
         isOnline: Bool = true, isNew: Bool = true, isTrusted: Bool = false,
         isLocal: Bool = false, isGateway: Bool = false) {
        self.id = id
        self.name = name
        self.customName = customName
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.vendor = vendor
        self.hostname = hostname
        self.kind = kind
        self.customKind = customKind
        self.services = services
        self.serviceObservations = serviceObservations
        self.latencyMS = latencyMS
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnline = isOnline
        self.isNew = isNew
        self.isTrusted = isTrusted
        self.isLocal = isLocal
        self.isGateway = isGateway
    }

    var displayName: String {
        let preferred = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = preferred?.isEmpty == false ? preferred! : automaticDisplayName
        return isLocal ? "\(base) (You)" : base
    }

    var automaticDisplayName: String {
        if isMeaningfulDetectedName(name) { return name }
        if let hostname, !hostname.isEmpty {
            let friendly = DeviceClassifier.friendlyName(hostname: hostname, ip: ipAddress)
            if isMeaningfulDetectedName(friendly) { return friendly }
        }
        if let last = ipAddress.split(separator: ".").last, Int(last) != nil { return "Device \(last)" }
        return "Unknown Device"
    }

    var detectedName: String {
        if isMeaningfulDetectedName(name) { return name }
        if let hostname, !hostname.isEmpty { return hostname }
        return "Unavailable"
    }

    var displayKind: DeviceKind { customKind ?? kind }
    var detectedKindLabel: String { kind == .unknown ? "Unknown" : kind.categoryLabel }
    var displayKindLabel: String { displayKind == .unknown ? "Unknown" : displayKind.categoryLabel }

    private func isMeaningfulDetectedName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "Unknown Device" && !trimmed.hasPrefix("Device ")
    }

    var connectionLabel: String {
        if isLocal { return "This Mac" }
        if let service = serviceObservations.first { return service.name }
        return services.isEmpty ? "Local network" : services.sorted().first ?? "Local network"
    }

    var vendorLabel: String {
        guard let vendor, !vendor.isEmpty, !usesPrivateMAC else { return "Unknown" }
        return vendor
    }

    var usesPrivateMAC: Bool {
        guard let first = macAddress?.split(separator: ":").first,
              let value = UInt8(first, radix: 16) else { return false }
        return value & 0x02 != 0
    }

    var formattedMACAddress: String? {
        guard let macAddress else { return nil }
        let components = macAddress.replacingOccurrences(of: "-", with: ":").split(separator: ":")
        guard components.count == 6,
              components.allSatisfy({ UInt8($0, radix: 16) != nil }) else { return macAddress.uppercased() }
        return components.map { component in
            let value = UInt8(component, radix: 16)!
            return String(format: "%02X", value)
        }.joined(separator: ":")
    }

    var macTypeLabel: String {
        guard let first = formattedMACAddress?.split(separator: ":").first,
              let value = UInt8(first, radix: 16) else { return "Unavailable" }
        if value & 0x01 != 0 { return "Indeterminate" }
        return value & 0x02 != 0 ? "Locally administered / private" : "Globally administered"
    }
}

struct NetworkInterfaceInfo: Equatable {
    var name: String = "Wi-Fi"
    var interfaceName: String = "en0"
    var ipAddress: String = "—"
    var netmask: String = "—"
    var gateway: String?
    var prefixLength: Int = 24

    var cidr: String { ipAddress == "—" ? "Waiting for network…" : "\(ipAddress)/\(prefixLength)" }
}

enum ActivityEventType: String, Codable, CaseIterable, Identifiable {
    case discovered, reachable, offline, returned, ipChanged, hostnameChanged, serviceObserved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .discovered: "Discovered"
        case .reachable: "Reachable"
        case .offline: "Offline"
        case .returned: "Returned"
        case .ipChanged: "IP Changed"
        case .hostnameChanged: "Name Changed"
        case .serviceObserved: "Service"
        }
    }
}

struct ActivityItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var date: Date
    var kind: DeviceKind
    var eventType: ActivityEventType = .discovered
    var deviceID: String?
}

enum ScanPhase: Equatable {
    case idle
    case preparing
    case probing(completed: Int, total: Int, found: Int, limited: Bool)
    case resolving
    case monitoring(found: Int)
    case complete
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Ready to scan"
        case .preparing: "Reading network configuration…"
        case let .probing(done, total, found, limited):
            limited
                ? "Large subnet · checked \(done)/\(total) · \(found) found"
                : "Checked \(done)/\(total) addresses · \(found) found"
        case .resolving: "Identifying discovered devices…"
        case .monitoring(let found): "Monitoring network · \(found) online"
        case .complete: "Scan complete"
        case .failed(let message): message
        }
    }
}

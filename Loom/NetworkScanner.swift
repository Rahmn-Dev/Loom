import Foundation
import Network
import Darwin
import OSLog

enum DiscoveryTrace {
#if DEBUG
    private static let lock = NSLock()
    private static var handle: FileHandle?
    private static let logger = Logger(subsystem: "com.loom.networkscanner", category: "Discovery")
    private static let formatter = ISO8601DateFormatter()

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Loom", isDirectory: true)
            .appendingPathComponent("scan-debug.log")
    }

    static func begin() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        writeLocked("SCAN BEGIN")
    }

    static func record(ip: String? = nil, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let scope = ip.map { " ip=\($0)" } ?? ""
        writeLocked("\(message)\(scope)")
    }

    static func finish(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        writeLocked("SCAN END \(message)")
        try? handle?.close()
        handle = nil
    }

    private static func writeLocked(_ message: String) {
        let line = "\(formatter.string(from: .now)) \(message)"
        logger.debug("\(line, privacy: .public)")
        if let data = "\(line)\n".data(using: .utf8) {
            try? handle?.write(contentsOf: data)
            try? handle?.synchronize()
        }
    }
#else
    static func begin() {}
    static func record(ip: String? = nil, _ message: String) {}
    static func finish(_ message: String) {}
#endif
}

enum DeviceIdentityResolver {
    static func match(for incoming: NetworkDevice, in devices: [NetworkDevice]) -> (index: Int, reason: String)? {
        if incoming.isLocal, let match = devices.firstIndex(where: \.isLocal) { return (match, "local device") }
        if incoming.isGateway, let match = devices.firstIndex(where: \.isGateway) { return (match, "gateway") }
        if let mac = normalizedMAC(incoming.macAddress),
           let match = devices.firstIndex(where: { normalizedMAC($0.macAddress) == mac }) {
            return (match, "MAC \(mac)")
        }
        if let match = devices.firstIndex(where: { $0.ipAddress == incoming.ipAddress }) {
            if let incomingMAC = normalizedMAC(incoming.macAddress),
               let existingMAC = normalizedMAC(devices[match].macAddress),
               incomingMAC != existingMAC {
                DiscoveryTrace.record(ip: incoming.ipAddress,
                                      "IP identity match rejected reason=conflicting MAC existing=\(existingMAC) incoming=\(incomingMAC)")
            } else {
                return (match, "IP address")
            }
        }
        if let hostname = incoming.hostname?.lowercased(), !hostname.isEmpty,
           let match = devices.firstIndex(where: { $0.hostname?.lowercased() == hostname }) {
            return (match, "hostname \(hostname)")
        }
        return nil
    }

    static func normalizedMAC(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let components = value.replacingOccurrences(of: "-", with: ":").split(separator: ":")
        guard components.count == 6,
              components.allSatisfy({ UInt8($0, radix: 16) != nil }) else { return nil }
        return components.map { String(format: "%02x", UInt8($0, radix: 16)!) }.joined(separator: ":")
    }
}

@MainActor
final class NetworkScanner: ObservableObject {
    @Published private(set) var devices: [NetworkDevice] = []
    @Published private(set) var activities: [ActivityItem] = []
    @Published private(set) var interface = NetworkInterfaceInfo()
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var isScanning = false
    @Published private(set) var scanTarget = ""
    @Published private(set) var inspectionDeviceID: String?
    @Published var selectedDevice: NetworkDevice?

    let settings: SettingsStore
    private let deviceRepository = DeviceRepository()
    private let activityRepository = ActivityRepository()
    private var scanTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private let bonjour = BonjourDiscovery()

    init(settings: SettingsStore) {
        self.settings = settings
        self.devices = deviceRepository.load().map { stored in
            var device = stored
            device.isOnline = false
            return device
        }
        self.activities = activityRepository.load()
    }

    var onlineDevices: [NetworkDevice] { devices.filter(\.isOnline) }

    var progress: Double {
        if case let .probing(done, total, _, _) = phase, total > 0 { return Double(done) / Double(total) }
        if case .monitoring = phase { return 1 }
        return phase == .complete ? 1 : (isScanning ? 0.03 : 0)
    }

    func startScanning() {
        guard !isScanning else { return }
        DiscoveryTrace.begin()
        DiscoveryTrace.record("scan requested; remembered_devices=\(devices.count)")
        scanTask?.cancel()
        monitorTask?.cancel()
        isScanning = true
        phase = .preparing
        devices = devices.map { stored in
            var device = stored
            device.isOnline = false
            return device
        }

        bonjour.onDevice = { [weak self] discovery in
            Task { @MainActor in self?.merge(discovery) }
        }
        if settings.bonjourDiscovery && settings.automaticDiscovery { bonjour.start() }

        scanTask = Task { [weak self] in
            guard let self else { return }
            let configuration = await Task.detached(priority: .userInitiated) { NetworkProbe.interfaceInfo() }.value
            guard !Task.isCancelled else { return }
            interface = configuration
            DiscoveryTrace.record("active interface=\(configuration.interfaceName) address=\(configuration.ipAddress) mask=\(configuration.netmask) prefix=/\(configuration.prefixLength) gateway=\(configuration.gateway ?? "unavailable")")

            guard configuration.ipAddress != "—" else {
                DiscoveryTrace.finish("failed reason=no active local network")
                phase = .failed("No active local network found")
                isScanning = false
                return
            }

            let localName = Host.current().localizedName ?? "This Mac"
            merge(NetworkDevice(name: localName, ipAddress: configuration.ipAddress,
                                kind: .computer, services: [], latencyMS: 0,
                                isLocal: true))
            if let gateway = configuration.gateway {
                merge(NetworkDevice(name: "Home Wi-Fi", ipAddress: gateway, kind: .router,
                                    services: ["Gateway"], isGateway: true))
            }

            let plan = NetworkProbe.scanPlan(for: configuration)
            scanTarget = plan.cidr
            DiscoveryTrace.record("subnet calculated cidr=\(plan.cidr) host_count=\(plan.subnetHostCount) candidates=\(plan.addresses.count) limited=\(plan.isLimited)")
            guard settings.activeSubnetDiscovery && settings.automaticDiscovery else {
                phase = .monitoring(found: onlineDevices.count)
                isScanning = false
                beginMonitoring(configuration: configuration)
                return
            }
            phase = .probing(completed: 0, total: plan.addresses.count, found: onlineDevices.count,
                             limited: plan.isLimited)
            await runSweep(plan: plan)
            guard !Task.isCancelled else {
                DiscoveryTrace.finish("cancelled after sweep")
                return
            }
            phase = .resolving
            await resolveDiscoveredNames()
            phase = .monitoring(found: onlineDevices.count)
            isScanning = false
            DiscoveryTrace.finish("complete checked=\(plan.addresses.count) displayed=\(devices.count) online=\(onlineDevices.count)")
            beginMonitoring(configuration: configuration)
        }
    }

    func stopScanning() {
        DiscoveryTrace.record("scan cancellation requested")
        scanTask?.cancel()
        monitorTask?.cancel()
        scanTask = nil
        monitorTask = nil
        bonjour.stop()
        isScanning = false
        phase = devices.isEmpty ? .idle : .complete
        DiscoveryTrace.finish("cancelled by user")
    }

    func scanAgain() { stopScanning(); startScanning() }

    func toggleTrusted(_ device: NetworkDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].isTrusted.toggle()
        devices[index].isNew = false
        selectedDevice = devices[index]
        schedulePersistence()
    }

    func renameDevice(_ device: NetworkDevice, customName: String?) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        devices[index].customName = trimmed?.isEmpty == false ? trimmed : nil
        devices[index].isNew = false
        if selectedDevice?.id == device.id { selectedDevice = devices[index] }
        schedulePersistence()
    }

    func clearDeviceHistory() {
        devices.removeAll()
        selectedDevice = nil
        deviceRepository.clear()
    }

    func clearActivityHistory() {
        activities.removeAll()
        activityRepository.clear()
    }

    func inspectCommonPorts(on device: NetworkDevice) {
        guard inspectionDeviceID == nil, !device.ipAddress.isEmpty else { return }
        inspectionDeviceID = device.id
        Task { [weak self] in
            guard let self else { return }
            let observations = await NetworkProbe.inspectCommonServices(at: device.ipAddress)
            guard !Task.isCancelled else { return }
            var update = device
            update.serviceObservations = observations
            update.services.formUnion(observations.map(\.name))
            merge(update)
            inspectionDeviceID = nil
        }
    }

    private func runSweep(plan: ScanPlan) async {
        let checksEnabled = settings.serviceDiscovery && settings.commonServiceChecks
        await NetworkProbe.scan(addresses: plan.addresses, checkCommonPorts: checksEnabled) { update in
            await MainActor.run { [weak self] in
                guard let self else {
                    DiscoveryTrace.record("batch dropped reason=scanner deallocated")
                    return
                }
                guard self.isScanning else {
                    DiscoveryTrace.record("batch dropped reason=scan no longer active completed=\(update.completed)")
                    return
                }
                update.devices.forEach(self.merge)
                self.phase = .probing(completed: update.completed, total: update.total,
                                      found: self.onlineDevices.count, limited: plan.isLimited)
            }
        }
    }

    private func resolveDiscoveredNames() async {
        let unresolved = devices.filter { $0.name == "Unknown Device" || $0.name.hasPrefix("Device ") }.map(\.ipAddress)
        guard !unresolved.isEmpty else { return }
        let resolved = await Task.detached(priority: .utility) {
            await NetworkProbe.resolveNames(for: unresolved)
        }.value
        resolved.forEach(merge)
    }

    private func beginMonitoring(configuration: NetworkInterfaceInfo) {
        monitorTask?.cancel()
        guard settings.backgroundMonitoring else {
            bonjour.stop()
            phase = .complete
            return
        }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            var secondsSinceBroadScan = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                guard settings.backgroundMonitoring else {
                    bonjour.stop()
                    phase = .complete
                    return
                }
                secondsSinceBroadScan += 20

                let knownAddresses = devices.filter { !$0.isLocal }.map(\.ipAddress)
                let observations = await NetworkProbe.monitorKnown(
                    addresses: knownAddresses,
                    checkCommonPorts: settings.serviceDiscovery && settings.commonServiceChecks
                )
                observations.forEach(merge)
                markStaleDevicesOffline()
                phase = .monitoring(found: onlineDevices.count)

                // Bonjour stays live continuously. Every five minutes, also repeat the
                // bounded active sweep because quiet devices can age out of ARP caches.
                if secondsSinceBroadScan >= settings.periodicRescanSeconds,
                   settings.activeSubnetDiscovery, settings.automaticDiscovery, !isScanning {
                    secondsSinceBroadScan = 0
                    isScanning = true
                    let plan = NetworkProbe.scanPlan(for: configuration)
                    phase = .probing(completed: 0, total: plan.addresses.count,
                                     found: onlineDevices.count, limited: plan.isLimited)
                    await runSweep(plan: plan)
                    guard !Task.isCancelled else { return }
                    await resolveDiscoveredNames()
                    isScanning = false
                    phase = .monitoring(found: onlineDevices.count)
                }
            }
        }
    }

    private func merge(_ incoming: NetworkDevice) {
        guard !incoming.ipAddress.isEmpty else {
            DiscoveryTrace.record("Device filtered reason=empty IP address")
            return
        }
        guard incoming.ipAddress != "0.0.0.0" else {
            DiscoveryTrace.record(ip: incoming.ipAddress, "Device filtered reason=unspecified address")
            return
        }
        guard !incoming.ipAddress.hasPrefix("127.") else {
            DiscoveryTrace.record(ip: incoming.ipAddress, "Device filtered reason=loopback address")
            return
        }
        let now = Date.now
        if let match = identityMatch(for: incoming) {
            let index = match.index
            var current = devices[index]
            DiscoveryTrace.record(ip: incoming.ipAddress,
                                  "Device merge matched=true reason=\(match.reason) existing_id=\(current.id)")
            let wasOnline = current.isOnline
            let oldIP = current.ipAddress
            let oldHostname = current.hostname
            let existingServiceIDs = Set(current.serviceObservations.map(\.id))
            let genericIncoming = incoming.name == "Unknown Device" || incoming.name.hasPrefix("Device ")
            if !genericIncoming { current.name = incoming.name }
            if !incoming.ipAddress.isEmpty { current.ipAddress = incoming.ipAddress }
            current.macAddress = incoming.formattedMACAddress ?? current.macAddress
            if !incoming.usesPrivateMAC { current.vendor = incoming.vendor ?? current.vendor }
            current.hostname = incoming.hostname ?? current.hostname
            current.services.formUnion(incoming.services)
            mergeServices(incoming.serviceObservations, into: &current, at: now)
            current.latencyMS = incoming.latencyMS ?? current.latencyMS
            current.lastSeen = now
            current.isOnline = true
            current.isGateway = current.isGateway || incoming.isGateway
            current.isLocal = current.isLocal || incoming.isLocal
            current.kind = DeviceClassifier.classify(name: current.name, services: current.services,
                                                     isGateway: current.isGateway, isLocal: current.isLocal)
            devices[index] = current

            if !wasOnline, now.timeIntervalSince(current.firstSeen) > 5 {
                recordEvent(.returned, device: current, title: "Device returned",
                            detail: "\(current.displayName) is reachable again")
                if settings.notifyDeviceReturned {
                    LocalNotificationService.send(title: "Device returned", body: current.displayName)
                }
            }
            if oldIP != current.ipAddress {
                recordEvent(.ipChanged, device: current, title: "IP address changed",
                            detail: "\(oldIP) → \(current.ipAddress)")
                notifyImportantChangeIfEnabled(title: "Device IP changed",
                                               body: "\(current.displayName): \(current.ipAddress)", device: current)
            }
            if let hostname = current.hostname, oldHostname != nil, oldHostname != hostname {
                recordEvent(.hostnameChanged, device: current, title: "Hostname changed", detail: hostname)
                notifyImportantChangeIfEnabled(title: "Device name changed",
                                               body: "\(current.displayName): \(hostname)", device: current)
            }
            for service in current.serviceObservations where !existingServiceIDs.contains(service.id) {
                recordEvent(.serviceObserved, device: current, title: "Service observed",
                            detail: "\(service.name) on \(current.displayName)")
                notifyImportantChangeIfEnabled(title: "New local service observed",
                                               body: "\(service.name) on \(current.displayName)", device: current)
            }
            if selectedDevice?.id == current.id { selectedDevice = current }
            DiscoveryTrace.record(ip: current.ipAddress,
                                  "SwiftUI publish displayed=true action=updated device_id=\(current.id) name=\(current.displayName)")
        } else {
            var device = incoming
            device.macAddress = incoming.formattedMACAddress
            device.firstSeen = now
            device.lastSeen = now
            device.isOnline = true
            device.isNew = !device.isLocal && !device.isGateway
            if device.usesPrivateMAC { device.vendor = nil }
            device.kind = DeviceClassifier.classify(name: device.name, services: device.services,
                                                     isGateway: device.isGateway, isLocal: device.isLocal)
            devices.append(device)
            DiscoveryTrace.record(ip: device.ipAddress,
                                  "Device created id=\(device.id) name=\(device.displayName) online=true")
            recordEvent(.discovered, device: device,
                        title: device.isLocal ? "This Mac detected" : "New device discovered",
                        detail: "\(device.displayName) · \(device.ipAddress)")
            if device.isNew, settings.notifyNewDevice {
                LocalNotificationService.send(title: "New device discovered", body: device.displayName)
            }
        }
        devices.sort { lhs, rhs in
            if lhs.isGateway != rhs.isGateway { return lhs.isGateway }
            if lhs.isLocal != rhs.isLocal { return lhs.isLocal }
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return NetworkProbe.ipValue(lhs.ipAddress) < NetworkProbe.ipValue(rhs.ipAddress)
        }
        schedulePersistence()
        if let published = devices.first(where: { $0.ipAddress == incoming.ipAddress }) {
            DiscoveryTrace.record(ip: incoming.ipAddress,
                                  "SwiftUI publish displayed=true action=inserted_or_sorted device_id=\(published.id) total=\(devices.count)")
        }
    }

    private func identityMatch(for incoming: NetworkDevice) -> (index: Int, reason: String)? {
        DeviceIdentityResolver.match(for: incoming, in: devices)
    }

    private func mergeServices(_ incoming: [NetworkServiceObservation], into device: inout NetworkDevice, at now: Date) {
        for observation in incoming {
            if let index = device.serviceObservations.firstIndex(where: { $0.id == observation.id }) {
                device.serviceObservations[index].lastSeen = now
            } else {
                device.serviceObservations.append(observation)
            }
            device.services.insert(observation.name)
        }
    }

    private func recordEvent(_ type: ActivityEventType, device: NetworkDevice,
                             title: String, detail: String) {
        let duplicate = activities.first {
            $0.deviceID == device.id && $0.eventType == type && $0.detail == detail &&
            Date.now.timeIntervalSince($0.date) < 60
        }
        guard duplicate == nil else { return }
        activities.insert(ActivityItem(title: title, detail: detail, date: .now, kind: device.kind,
                                       eventType: type, deviceID: device.id), at: 0)
        activityRepository.save(activities)
    }

    private func notifyImportantChangeIfEnabled(title: String, body: String, device: NetworkDevice) {
        guard settings.notifyImportantChanges,
              Date.now.timeIntervalSince(device.firstSeen) > 60 else { return }
        LocalNotificationService.send(title: title, body: body)
    }

    private func markStaleDevicesOffline() {
        let cutoff = Date.now.addingTimeInterval(-90)
        for index in devices.indices where devices[index].isOnline && !devices[index].isLocal &&
            devices[index].lastSeen < cutoff {
            devices[index].isOnline = false
            recordEvent(.offline, device: devices[index], title: "Device appears offline",
                        detail: "\(devices[index].displayName) has not been observed recently")
        }
        schedulePersistence()
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            deviceRepository.save(devices)
            activityRepository.save(activities)
        }
    }
}

private final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onDevice: ((NetworkDevice) -> Void)?
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private let types = ["_airplay._tcp.", "_googlecast._tcp.", "_hap._tcp.", "_http._tcp.",
                         "_ipp._tcp.", "_raop._tcp.", "_smb._tcp.", "_ssh._tcp."]

    func start() {
        stop()
        for type in types {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
        browsers.removeAll()
        services.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let ip = sender.addresses?.compactMap(Self.ipv4Address).first else { return }
        let cleanType = sender.type.replacingOccurrences(of: ".", with: "")
        let friendly = NetworkProbe.friendlyServiceName(type: sender.type, port: UInt16(clamping: sender.port))
        let observation = NetworkServiceObservation(name: friendly, type: cleanType,
                                                    port: sender.port > 0 ? UInt16(clamping: sender.port) : nil,
                                                    evidence: .discovered)
        onDevice?(NetworkDevice(name: sender.name, ipAddress: ip, services: [friendly],
                                serviceObservations: [observation]))
    }

    private static func ipv4Address(_ data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }
            let sockaddrPointer = base.assumingMemoryBound(to: sockaddr.self)
            guard Int32(sockaddrPointer.pointee.sa_family) == AF_INET else { return nil }
            var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        }
    }
}

struct ScanPlan: Sendable {
    let addresses: [String]
    let subnetHostCount: Int
    let isLimited: Bool
    let cidr: String
}

struct ScanUpdate: Sendable {
    let completed: Int
    let total: Int
    let devices: [NetworkDevice]
}

private struct ProbeObservation: Sendable {
    let ip: String
    let icmpReachable: Bool
    let openPorts: [UInt16]
    let latencyMS: Int?

    var reachabilityObserved: Bool { icmpReachable || !openPorts.isEmpty }
}

enum NetworkProbe {
    private static let maximumInitialHosts = 4_094
    private static let concurrencyLimit = 48
    private static let tcpPorts: [UInt16] = [80, 443, 22, 445, 548, 62078]

    static func interfaceInfo() -> NetworkInterfaceInfo {
        var result = NetworkInterfaceInfo()
        let route = defaultRoute()
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return result }
        defer { freeifaddrs(pointer) }

        var candidates: [(name: String, ip: String, mask: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor?.pointee {
            defer { cursor = item.ifa_next }
            guard item.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(item.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let interfaceName = String(cString: item.ifa_name)
            guard let ip = addressString(item.ifa_addr), !ip.hasPrefix("169.254") else { continue }
            candidates.append((interfaceName, ip, addressString(item.ifa_netmask) ?? "255.255.255.0"))
        }

        let selected = candidates.first(where: { $0.name == route.interfaceName })
            ?? candidates.first(where: { $0.name == "en0" })
            ?? candidates.first
        if let selected {
            result = NetworkInterfaceInfo(name: selected.name.hasPrefix("en") ? "Home Wi-Fi" : selected.name,
                                          interfaceName: selected.name, ipAddress: selected.ip,
                                          netmask: selected.mask, gateway: route.gateway,
                                          prefixLength: prefixLength(selected.mask))
        }
        return result
    }

    static func scanPlan(for info: NetworkInterfaceInfo) -> ScanPlan {
        let parts = info.ipAddress.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else {
            return ScanPlan(addresses: [], subnetHostCount: 0, isLimited: false, cidr: "Unavailable")
        }
        let own = ipValue(info.ipAddress)
        let mask = ipValue(info.netmask)
        let network = own & mask
        let broadcast = network | ~mask
        let cidr = "\(ipString(network))/\(info.prefixLength)"
        guard broadcast > network else {
            return ScanPlan(addresses: [], subnetHostCount: 0, isLimited: false, cidr: cidr)
        }

        if info.prefixLength == 31 {
            let peer = own == network ? broadcast : network
            return ScanPlan(addresses: [ipString(peer)], subnetHostCount: 2, isLimited: false, cidr: cidr)
        }

        let firstHost = network &+ 1
        let lastHost = broadcast &- 1
        guard lastHost >= firstHost else {
            return ScanPlan(addresses: [], subnetHostCount: 0, isLimited: false, cidr: cidr)
        }
        let rawCount = UInt64(lastHost) - UInt64(firstHost) + 1
        let hostCount = Int(min(rawCount, UInt64(Int.max)))

        if hostCount <= maximumInitialHosts {
            let addresses = (firstHost...lastHost).filter { $0 != own }.map(ipString)
            return ScanPlan(addresses: addresses, subnetHostCount: hostCount, isLimited: false, cidr: cidr)
        }

        // Very large enterprise/VPN ranges are bounded. Prioritize a contiguous window
        // around this Mac and always include the default gateway. Later periodic sweeps
        // repeat discovery without creating tens of thousands of simultaneous probes.
        let half = UInt32(maximumInitialHosts / 2)
        var start = own > half ? own - half : firstHost
        start = max(firstHost, min(start, lastHost - UInt32(maximumInitialHosts - 1)))
        let end = min(lastHost, start + UInt32(maximumInitialHosts - 1))
        var values = Array(start...end).filter { $0 != own }
        if let gateway = info.gateway {
            let gatewayValue = ipValue(gateway)
            if gatewayValue >= firstHost, gatewayValue <= lastHost, !values.contains(gatewayValue), gatewayValue != own {
                values.append(gatewayValue)
            }
        }
        return ScanPlan(addresses: values.map(ipString), subnetHostCount: hostCount, isLimited: true, cidr: cidr)
    }

    static func scan(addresses: [String], checkCommonPorts: Bool = true,
                     onUpdate: @escaping @Sendable (ScanUpdate) async -> Void) async {
        guard !addresses.isEmpty else {
            DiscoveryTrace.record("scan skipped reason=empty candidate range")
            await onUpdate(ScanUpdate(completed: 0, total: 0, devices: []))
            return
        }
        let allowed = Set(addresses)
        var observed: [String: ProbeObservation] = [:]
        for (index, address) in addresses.enumerated() {
            DiscoveryTrace.record(ip: address, "candidate generated index=\(index + 1)/\(addresses.count)")
        }

        // A batch is the worker pool: at most `concurrencyLimit` hosts are probed at once.
        // UDP triggers link-layer resolution, ICMP matches Terminal ping behavior, and
        // successful TCP connects add service evidence. Any single positive signal is
        // enough to publish an Unknown Device; failures never prove that a host is offline.
        for batchStart in stride(from: 0, to: addresses.count, by: concurrencyLimit) {
            if Task.isCancelled {
                DiscoveryTrace.record("scan loop stopped reason=task cancelled before batch start=\(batchStart)")
                return
            }
            let end = min(batchStart + concurrencyLimit, addresses.count)
            let batch = Array(addresses[batchStart..<end])
            let results = await withTaskGroup(of: ProbeObservation.self, returning: [ProbeObservation].self) { group in
                for address in batch {
                    group.addTask { await probeHostWithoutBlockingExecutor(address, checkCommonPorts: checkCommonPorts) }
                }
                var values: [ProbeObservation] = []
                for await value in group { values.append(value) }
                return values
            }
            for result in results where result.reachabilityObserved { observed[result.ip] = result }

            // Re-read after every batch instead of waiting for the whole subnet. Newly
            // resolved neighbors therefore stream into SwiftUI while scanning continues.
            try? await Task.sleep(for: .milliseconds(70))
            let neighbors = arpNeighbors().filter { allowed.contains($0.ip) }
            let neighborMap = Dictionary(uniqueKeysWithValues: neighbors.map { ($0.ip, $0.mac) })
            let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.ip, $0) })
            var targetedNeighborMap: [String: String] = [:]
            for address in batch {
                let result = resultMap[address]
                var mac = neighborMap[address]
                if mac == nil, result?.reachabilityObserved == true {
                    mac = arpNeighbor(for: address)?.mac
                    targetedNeighborMap[address] = mac
                }
                DiscoveryTrace.record(ip: address, mac.map { "neighbor/ARP result=found mac=\($0)" } ?? "neighbor/ARP result=not found")
                let shouldCreate = mac != nil || result?.reachabilityObserved == true
                if shouldCreate {
                    let basis: String
                    if result?.icmpReachable == true { basis = "ICMP reply" }
                    else if let ports = result?.openPorts, !ports.isEmpty { basis = "TCP open ports \(ports)" }
                    else { basis = "neighbor table entry" }
                    DiscoveryTrace.record(ip: address, "hostname result=pending asynchronous resolution")
                    DiscoveryTrace.record(ip: address, "Device model created=true basis=\(basis) initial_name=Unknown Device online=true")
                } else {
                    DiscoveryTrace.record(ip: address, "hostname result=not attempted reason=no positive observation")
                    DiscoveryTrace.record(ip: address, "Device model created=false filtered/dropped reason=no positive ICMP, TCP, or neighbor observation")
                }
            }
            var devices = neighbors.map { neighbor in
                let observation = observed[neighbor.ip]
                let serviceDetails = observation?.openPorts.map {
                    NetworkServiceObservation(name: serviceName(for: $0), port: $0, evidence: .open)
                } ?? []
                let services = Set(serviceDetails.map(\.name))
                return NetworkDevice(name: DeviceClassifier.friendlyName(hostname: nil, ip: neighbor.ip),
                                     ipAddress: neighbor.ip, macAddress: neighbor.mac,
                                     services: services, serviceObservations: serviceDetails,
                                     latencyMS: observation?.latencyMS)
            }

            // A successful ICMP reply or TCP connection is valid reachability evidence
            // even if the ARP command has not published its entry yet.
            let neighborIPs = Set(neighbors.map(\.ip))
            devices += observed.values.filter { !neighborIPs.contains($0.ip) }.map { observation in
                let serviceDetails = observation.openPorts.map {
                    NetworkServiceObservation(name: serviceName(for: $0), port: $0, evidence: .open)
                }
                return NetworkDevice(name: DeviceClassifier.friendlyName(hostname: nil, ip: observation.ip),
                              ipAddress: observation.ip, macAddress: targetedNeighborMap[observation.ip],
                              services: Set(serviceDetails.map(\.name)),
                              serviceObservations: serviceDetails,
                              latencyMS: observation.latencyMS)
            }
            await onUpdate(ScanUpdate(completed: end, total: addresses.count, devices: devices))
        }

        guard !Task.isCancelled else {
            DiscoveryTrace.record("final neighbor read skipped reason=task cancelled")
            return
        }
        let finalDevices = neighborDevices(for: addresses)
        DiscoveryTrace.record("final neighbor/ARP re-read complete matches=\(finalDevices.count)")
        await onUpdate(ScanUpdate(completed: addresses.count, total: addresses.count, devices: finalDevices))
    }

    static func neighborDevices(for addresses: [String]) -> [NetworkDevice] {
        let allowed = Set(addresses)
        return arpNeighbors().filter { allowed.contains($0.ip) }.map {
            NetworkDevice(name: DeviceClassifier.friendlyName(hostname: nil, ip: $0.ip),
                          ipAddress: $0.ip, macAddress: $0.mac)
        }
    }

    static func monitorKnown(addresses: [String], checkCommonPorts: Bool) async -> [NetworkDevice] {
        let unique = Array(Set(addresses.filter { !$0.isEmpty && !$0.hasPrefix("127.") }))
        guard !unique.isEmpty else { return [] }
        var results: [ProbeObservation] = []
        for start in stride(from: 0, to: unique.count, by: concurrencyLimit) {
            guard !Task.isCancelled else { break }
            let end = min(start + concurrencyLimit, unique.count)
            let batch = await withTaskGroup(of: ProbeObservation.self, returning: [ProbeObservation].self) { group in
                for address in unique[start..<end] {
                    group.addTask { await probeHostWithoutBlockingExecutor(address, checkCommonPorts: checkCommonPorts) }
                }
                var values: [ProbeObservation] = []
                for await value in group { values.append(value) }
                return values
            }
            results.append(contentsOf: batch)
        }
        try? await Task.sleep(for: .milliseconds(80))
        let neighborMap = Dictionary(uniqueKeysWithValues: arpNeighbors().map { ($0.ip, $0.mac) })
        return results.compactMap { result in
            guard result.reachabilityObserved || neighborMap[result.ip] != nil else { return nil }
            let serviceDetails = result.openPorts.map {
                NetworkServiceObservation(name: serviceName(for: $0), port: $0, evidence: .open)
            }
            return NetworkDevice(name: DeviceClassifier.friendlyName(hostname: nil, ip: result.ip),
                                 ipAddress: result.ip, macAddress: neighborMap[result.ip],
                                 services: Set(serviceDetails.map(\.name)),
                                 serviceObservations: serviceDetails, latencyMS: result.latencyMS)
        }
    }

    static func resolveNames(for addresses: [String]) async -> [NetworkDevice] {
        var output: [NetworkDevice] = []
        let unique = Array(Set(addresses))
        for start in stride(from: 0, to: unique.count, by: 24) {
            guard !Task.isCancelled else { break }
            let end = min(start + 24, unique.count)
            let batch = await withTaskGroup(of: NetworkDevice?.self, returning: [NetworkDevice].self) { group in
                for address in unique[start..<end] {
                    group.addTask {
                        guard let host = reverseDNS(address) else {
                            DiscoveryTrace.record(ip: address, "hostname result=unavailable; retaining Unknown Device")
                            return nil
                        }
                        DiscoveryTrace.record(ip: address, "hostname result=found value=\(host)")
                        return NetworkDevice(name: DeviceClassifier.friendlyName(hostname: host, ip: address),
                                             ipAddress: address, hostname: host)
                    }
                }
                var values: [NetworkDevice] = []
                for await item in group { if let item { values.append(item) } }
                return values
            }
            output.append(contentsOf: batch)
        }
        return output
    }

    static func ipValue(_ address: String) -> UInt32 {
        address.split(separator: ".").reduce(UInt32(0)) { ($0 << 8) | (UInt32($1) ?? 0) }
    }

    private static func ipString(_ value: UInt32) -> String {
        "\((value >> 24) & 255).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
    }

    private static func addressString(_ address: UnsafePointer<sockaddr>?) -> String? {
        guard let address else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                          NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    private static func prefixLength(_ mask: String) -> Int {
        mask.split(separator: ".").compactMap { UInt8($0) }.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    private static func defaultRoute() -> (gateway: String?, interfaceName: String?) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        func value(after key: String) -> String? {
            text.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key) }?
                .split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return (value(after: "gateway:"), value(after: "interface:"))
    }

    private static func probeHost(_ ip: String, checkCommonPorts: Bool) -> ProbeObservation {
        guard !Task.isCancelled else {
            DiscoveryTrace.record(ip: ip, "probe attempted=false reason=task already cancelled")
            return ProbeObservation(ip: ip, icmpReachable: false, openPorts: [], latencyMS: nil)
        }
        DiscoveryTrace.record(ip: ip, "probe attempted=true mechanisms=UDP/5353,UDP/9,ICMP echo\(checkCommonPorts ? ",TCP/\(tcpPorts)" : "")")
        let udp5353 = sendUDPProbe(to: ip, port: 5353)
        let udp9 = sendUDPProbe(to: ip, port: 9)
        DiscoveryTrace.record(ip: ip, "probe result mechanism=UDP/5353 submitted=\(udp5353)")
        DiscoveryTrace.record(ip: ip, "probe result mechanism=UDP/9 submitted=\(udp9)")

        let icmp = icmpEcho(ip: ip, timeoutMS: 1_000)
        DiscoveryTrace.record(ip: ip, "probe result mechanism=ICMP reachable=\(icmp.reachable) latency_ms=\(icmp.latencyMS.map(String.init) ?? "unavailable") detail=\(icmp.detail)")

        guard checkCommonPorts else {
            DiscoveryTrace.record(ip: ip, "probe result mechanism=TCP attempted=false reason=common service checks disabled")
            return ProbeObservation(ip: ip, icmpReachable: icmp.reachable,
                                    openPorts: [], latencyMS: icmp.latencyMS)
        }
        var openPorts: [UInt16] = []
        var bestLatency = icmp.latencyMS
        for port in tcpPorts {
            let started = DispatchTime.now().uptimeNanoseconds
            let connected = tcpConnect(ip: ip, port: port, timeoutMS: 120)
            DiscoveryTrace.record(ip: ip, "probe result mechanism=TCP port=\(port) connected=\(connected)")
            if connected {
                let elapsed = DispatchTime.now().uptimeNanoseconds - started
                openPorts.append(port)
                let latency = max(1, Int(elapsed / 1_000_000))
                bestLatency = min(bestLatency ?? latency, latency)
            }
        }
        DiscoveryTrace.record(ip: ip, "reachability observed=\(icmp.reachable || !openPorts.isEmpty) icmp=\(icmp.reachable) open_ports=\(openPorts)")
        return ProbeObservation(ip: ip, icmpReachable: icmp.reachable,
                                openPorts: openPorts, latencyMS: bestLatency)
    }

    /// Process.waitUntilExit and POSIX connect/poll are intentionally synchronous.
    /// Move that work off Swift's cooperative executor so a bounded task group really
    /// runs its worker pool concurrently instead of starving unrelated async work.
    private static func probeHostWithoutBlockingExecutor(_ ip: String,
                                                         checkCommonPorts: Bool) async -> ProbeObservation {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: probeHost(ip, checkCommonPorts: checkCommonPorts))
            }
        }
    }

    private static func icmpEcho(ip: String, timeoutMS: Int) -> (reachable: Bool, latencyMS: Int?, detail: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-n", "-c", "1", "-W", String(timeoutMS), ip]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (false, nil, "launch_failed=\(error.localizedDescription.replacingOccurrences(of: " ", with: "_"))")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let latency = parsePingLatency(output)
        let reachable = process.terminationStatus == 0 && output.contains("bytes from")
        return (reachable, latency, "exit=\(process.terminationStatus)")
    }

    private static func parsePingLatency(_ output: String) -> Int? {
        let pattern = #"time[=<]([0-9]+(?:\.[0-9]+)?)\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let value = Double(output[range]) else { return nil }
        return max(1, Int(value.rounded()))
    }

    private static func tcpConnect(ip: String, port: UInt16, timeoutMS: Int32) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let existingFlags = fcntl(fd, F_GETFL, 0)
        guard existingFlags >= 0, fcntl(fd, F_SETFL, existingFlags | O_NONBLOCK) == 0 else { return false }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &destination.sin_addr) == 1 else { return false }
        let connectionResult = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectionResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, timeoutMS) > 0 else { return false }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else { return false }
        return socketError == 0
    }

    private static func sendUDPProbe(to ip: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &destination.sin_addr) == 1 else { return false }
        var byte: UInt8 = 0
        return withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                sendto(fd, &byte, 1, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 1
            }
        }
    }

    private static func serviceName(for port: UInt16) -> String {
        switch port {
        case 80: "HTTP"
        case 443: "HTTPS"
        case 22: "SSH"
        case 445: "SMB"
        case 548: "AFP"
        case 62078: "Apple device"
        default: "TCP \(port)"
        }
    }

    static func friendlyServiceName(type: String, port: UInt16?) -> String {
        let value = type.lowercased()
        if value.contains("airplay") { return "AirPlay" }
        if value.contains("googlecast") { return "Google Cast" }
        if value.contains("_hap") { return "HomeKit" }
        if value.contains("_ipp") { return "Printing" }
        if value.contains("_raop") { return "AirPlay Audio" }
        if value.contains("_smb") { return "SMB" }
        if value.contains("_ssh") { return "SSH" }
        if value.contains("_http") { return "HTTP" }
        return port.map(serviceName(for:)) ?? type.replacingOccurrences(of: ".", with: "")
    }

    static func inspectCommonServices(at ip: String) async -> [NetworkServiceObservation] {
        let expandedPorts: [UInt16] = [20, 21, 22, 23, 53, 80, 110, 139, 143, 443, 445, 548,
                                       631, 993, 995, 1883, 3389, 5000, 5353, 5900, 8000, 8080,
                                       8443, 9100, 62078]
        return await withTaskGroup(of: NetworkServiceObservation?.self, returning: [NetworkServiceObservation].self) { group in
            for port in expandedPorts {
                group.addTask {
                    guard tcpConnect(ip: ip, port: port, timeoutMS: 160) else { return nil }
                    return NetworkServiceObservation(name: serviceName(for: port), port: port, evidence: .open)
                }
            }
            var output: [NetworkServiceObservation] = []
            for await item in group { if let item { output.append(item) } }
            return output.sorted { ($0.port ?? 0) < ($1.port ?? 0) }
        }
    }

    private static func arpNeighbors() -> [(ip: String, mac: String)] {
        let native = nativeIPv4Neighbors()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            DiscoveryTrace.record("neighbor/ARP command attempted=false reason=launch failed detail=\(error.localizedDescription)")
            return []
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let neighbors = parseARPTable(text)
        DiscoveryTrace.record("neighbor/ARP command attempted=true exit=\(process.terminationStatus) parsed=\(neighbors.count) native=\(native.count)")
        if process.terminationStatus != 0 {
            let detail = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DiscoveryTrace.record("neighbor/ARP command failed detail=\(detail.isEmpty ? "no output" : detail)")
        }
        var merged = Dictionary(uniqueKeysWithValues: native.map { ($0.ip, $0.mac) })
        for neighbor in neighbors { merged[neighbor.ip] = neighbor.mac }
        return merged.map { (ip: $0.key, mac: $0.value) }
    }

    /// Read the IPv4 link-layer neighbor routes directly. This is the same kernel
    /// information exposed by `arp`, but avoids depending exclusively on parsing a
    /// subprocess whose output can be restricted by some launch environments.
    static func nativeIPv4Neighbors() -> [(ip: String, mac: String)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var byteCount = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &byteCount, nil, 0) == 0, byteCount > 0 else {
            DiscoveryTrace.record("native neighbor read unavailable errno=\(errno)")
            return []
        }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let readResult = bytes.withUnsafeMutableBytes { buffer in
            sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &byteCount, nil, 0)
        }
        guard readResult == 0 else {
            DiscoveryTrace.record("native neighbor read failed errno=\(errno)")
            return []
        }

        var output: [(ip: String, mac: String)] = []
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var messageOffset = 0
            while messageOffset + MemoryLayout<rt_msghdr>.size <= byteCount {
                let headerPointer = base.advanced(by: messageOffset).assumingMemoryBound(to: rt_msghdr.self)
                let header = headerPointer.pointee
                let messageLength = Int(header.rtm_msglen)
                guard messageLength >= MemoryLayout<rt_msghdr>.size,
                      messageOffset + messageLength <= byteCount else { break }

                var addressOffset = messageOffset + MemoryLayout<rt_msghdr>.size
                var ip: String?
                var mac: String?
                for index in 0..<Int(RTAX_MAX) where (header.rtm_addrs & (Int32(1) << Int32(index))) != 0 {
                    guard addressOffset + MemoryLayout<sockaddr>.size <= messageOffset + messageLength else { break }
                    let socketAddress = base.advanced(by: addressOffset).assumingMemoryBound(to: sockaddr.self).pointee
                    let rawLength = Int(socketAddress.sa_len)
                    // Darwin routing socket addresses use 32-bit alignment even in a
                    // 64-bit process (the kernel ROUNDUP contract for this table).
                    let alignedLength = rawLength > 0 ? (rawLength + 3) & ~3 : 4

                    if index == Int(RTAX_DST), Int32(socketAddress.sa_family) == AF_INET {
                        var address = base.advanced(by: addressOffset)
                            .assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        if inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil {
                            ip = String(cString: text)
                        }
                    } else if index == Int(RTAX_GATEWAY), Int32(socketAddress.sa_family) == AF_LINK {
                        let link = base.advanced(by: addressOffset).assumingMemoryBound(to: sockaddr_dl.self).pointee
                        let addressLength = Int(link.sdl_alen)
                        let nameLength = Int(link.sdl_nlen)
                        if addressLength == 6, 8 + nameLength + addressLength <= rawLength {
                            let start = base.advanced(by: addressOffset + 8 + nameLength)
                                .assumingMemoryBound(to: UInt8.self)
                            mac = (0..<addressLength).map { String(format: "%02X", start[$0]) }
                                .joined(separator: ":")
                        }
                    }
                    addressOffset += alignedLength
                }
                if let ip, let mac, mac != "00:00:00:00:00:00" { output.append((ip, mac)) }
                messageOffset += messageLength
            }
        }
        DiscoveryTrace.record("native neighbor read complete parsed=\(output.count)")
        return output
    }

    private static func arpNeighbor(for ip: String) -> (ip: String, mac: String)? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            DiscoveryTrace.record(ip: ip, "targeted neighbor/ARP attempted=false reason=launch failed detail=\(error.localizedDescription)")
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let neighbor = parseARPTable(text).first { $0.ip == ip }
        DiscoveryTrace.record(ip: ip, "targeted neighbor/ARP attempted=true exit=\(process.terminationStatus) result=\(neighbor?.mac ?? "not found")")
        if process.terminationStatus != 0 {
            let detail = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DiscoveryTrace.record(ip: ip, "targeted neighbor/ARP failed detail=\(detail.isEmpty ? "no output" : detail)")
        }
        return neighbor
    }

    static func parseARPTable(_ text: String) -> [(ip: String, mac: String)] {
        let pattern = #"\((\d{1,3}(?:\.\d{1,3}){3})\) at ([0-9a-fA-F:]{11,17})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let string = String(line)
            let range = NSRange(string.startIndex..., in: string)
            guard let match = regex.firstMatch(in: string, range: range),
                  let ipRange = Range(match.range(at: 1), in: string),
                  let macRange = Range(match.range(at: 2), in: string) else { return nil }
            return (String(string[ipRange]), String(string[macRange]).uppercased())
        }
    }

    private static func reverseDNS(_ ip: String) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, ip, &address.sin_addr)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        return result == 0 ? String(cString: host) : nil
    }
}

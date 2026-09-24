import SwiftUI

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 27, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(LoomTheme.secondaryText)
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).padding(.horizontal, 16).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(LoomTheme.stroke)))
                }
                .buttonStyle(LoomHoverButtonStyle(cornerRadius: 10, fillOpacity: 0.10, hoverScale: 1.025))
            }
        }
    }
}

private enum DeviceListFilter: String, CaseIterable, Identifiable {
    case all = "All", online = "Online", new = "New", unknown = "Unknown", offline = "Offline"
    var id: String { rawValue }
}

struct DevicesSectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @State private var filter: DeviceListFilter = .all
    @State private var query = ""

    private var visibleDevices: [NetworkDevice] {
        scanner.devices.filter { device in
            let filterMatches: Bool = switch filter {
            case .all: true
            case .online: device.isOnline
            case .new: device.isNew
            case .unknown: !device.isTrusted && !device.isLocal
            case .offline: !device.isOnline
            }
            let queryMatches = query.isEmpty || device.displayName.localizedCaseInsensitiveContains(query) ||
                device.ipAddress.localizedCaseInsensitiveContains(query) ||
                (device.hostname?.localizedCaseInsensitiveContains(query) ?? false)
            return filterMatches && queryMatches
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "Devices", subtitle: "Remembered identities and live observations from this Mac.",
                          actionTitle: scanner.isScanning ? "Stop Scan" : "Scan Again") {
                scanner.isScanning ? scanner.stopScanning() : scanner.scanAgain()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    filterControls
                    Spacer()
                    searchField.frame(width: 230)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal) { HStack(spacing: 8) { filterControls } }
                        .scrollIndicators(.hidden)
                    searchField.frame(maxWidth: .infinity)
                }
            }

            if visibleDevices.isEmpty {
                ContentUnavailableView("No matching devices", systemImage: "network.slash",
                                       description: Text("Only devices observed on the local network appear here."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 285, maximum: 380), spacing: 14)], spacing: 14) {
                        ForEach(visibleDevices) { device in
                            Button { scanner.selectedDevice = device } label: {
                                DeviceCard(device: device)
                            }
                            .buttonStyle(LoomHoverButtonStyle(cornerRadius: 16, fillOpacity: 0.085, hoverScale: 1.012))
                            .help("Open \(device.displayName)")
                        }
                    }.padding(2)
                }.scrollIndicators(.hidden)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func count(for filter: DeviceListFilter) -> Int {
        switch filter {
        case .all: scanner.devices.count
        case .online: scanner.devices.filter(\.isOnline).count
        case .new: scanner.devices.filter(\.isNew).count
        case .unknown: scanner.devices.filter { !$0.isTrusted && !$0.isLocal }.count
        case .offline: scanner.devices.filter { !$0.isOnline }.count
        }
    }

    @ViewBuilder private var filterControls: some View {
        ForEach(DeviceListFilter.allCases) { item in
            Button {
                filter = item
            } label: {
                Text("\(item.rawValue)  \(count(for: item))")
                    .font(.system(size: 12, weight: filter == item ? .semibold : .regular))
                    .padding(.horizontal, 12).frame(height: 31)
                    .background(Capsule().fill(filter == item ? LoomTheme.primary.opacity(0.55) : Color.white.opacity(0.06)))
            }.buttonStyle(LoomHoverButtonStyle(cornerRadius: 16, fillOpacity: 0.07, hoverScale: 1.035))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(LoomTheme.secondaryText)
            TextField("Search devices", text: $query).textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(LoomTheme.stroke)))
    }
}

private struct DeviceCard: View {
    let device: NetworkDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                DeviceGlyph(kind: device.displayKind, size: 48).opacity(device.isOnline ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(device.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if device.isNew { Text("NEW").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
                    }
                    HStack(spacing: 6) {
                        StatusDot(color: device.isOnline ? LoomTheme.green : .gray, size: 7)
                        Text(device.isOnline ? "Online" : "Last seen \(device.lastSeen.formatted(.relative(presentation: .numeric)))")
                    }.font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: device.isTrusted ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(device.isTrusted ? LoomTheme.green : LoomTheme.secondaryText)
                    Text(device.isTrusted ? "Trusted" : "Needs Review")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(device.isTrusted ? LoomTheme.green : LoomTheme.secondaryText)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow { label("IP"); value(device.ipAddress) }
                GridRow { label("MAC"); value(device.formattedMACAddress ?? "Unavailable") }
                GridRow { label("MAC Type"); value(device.macTypeLabel) }
                GridRow { label("Vendor"); value(device.vendorLabel) }
                GridRow { label("Hostname"); value(device.hostname ?? "Unavailable") }
                GridRow { label("Latency"); value(device.latencyMS.map { "\($0) ms" } ?? "Unavailable") }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText).frame(width: 58, alignment: .leading)
    }
    private func value(_ text: String) -> some View { Text(text).font(.system(size: 11)).lineLimit(1) }
}

struct NetworkMapSectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Network Map",
                          subtitle: "Observed LAN membership. Lines indicate visibility on the same network—not physical routing.",
                          actionTitle: scanner.isScanning ? "Stop Scan" : "Scan Again") {
                scanner.isScanning ? scanner.stopScanning() : scanner.scanAgain()
            }
            HStack(spacing: 10) {
                mapStat("\(scanner.onlineDevices.count)", "Online", LoomTheme.green)
                mapStat("\(scanner.devices.filter { !$0.isOnline }.count)", "Offline", .gray)
                mapStat("\(scanner.devices.filter(\.isNew).count)", "New", .orange)
                Spacer()
                Text(scanner.phase.label).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
            }
            NetworkMapView().glassCard(radius: 20).padding(.top, 2)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mapStat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 7) { Text(value).fontWeight(.bold).foregroundStyle(color); Text(label).foregroundStyle(LoomTheme.secondaryText) }
            .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

struct ActivitySectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @State private var type = "All"
    @State private var deviceID = "All"

    private var events: [ActivityItem] {
        scanner.activities.filter {
            (type == "All" || $0.eventType.rawValue == type) && (deviceID == "All" || $0.deviceID == deviceID)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "Activity", subtitle: "A local timeline built only from observed network changes.")
            HStack {
                Picker("Event", selection: $type) {
                    Text("All Events").tag("All")
                    ForEach(ActivityEventType.allCases) { Text($0.label).tag($0.rawValue) }
                }.frame(width: 170)
                Picker("Device", selection: $deviceID) {
                    Text("All Devices").tag("All")
                    ForEach(scanner.devices) { Text($0.displayName).tag($0.id) }
                }.frame(width: 220)
                Spacer()
            }
            if events.isEmpty {
                ContentUnavailableView("No observed activity", systemImage: "clock.arrow.circlepath",
                                       description: Text("Events appear when Loom observes real device or service changes."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            Button {
                                if let id = event.deviceID,
                                   let device = scanner.devices.first(where: { $0.id == id }) {
                                    scanner.selectedDevice = device
                                }
                            } label: { HStack(spacing: 14) {
                                DeviceGlyph(kind: activityDeviceKind(event), size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(activityDeviceName(event)).font(.system(size: 13, weight: .semibold))
                                    Text(activityDetail(event)).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                                }
                                Spacer()
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                            }.padding(.horizontal, 16).frame(minHeight: 62).contentShape(Rectangle()) }
                            .buttonStyle(LoomHoverButtonStyle(cornerRadius: 9, fillOpacity: 0.055, hoverScale: 1.002))
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }.glassCard(radius: 16)
                }.scrollIndicators(.hidden)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityDeviceName(_ event: ActivityItem) -> String {
        guard let id = event.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else { return event.title }
        return device.displayName
    }

    private func activityDeviceKind(_ event: ActivityItem) -> DeviceKind {
        guard let id = event.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else { return event.kind }
        return device.displayKind
    }

    private func activityDetail(_ event: ActivityItem) -> String {
        guard let id = event.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else {
            return "\(event.title) · \(event.detail)"
        }
        let updated = event.detail.contains(device.displayName)
            ? event.detail
            : event.detail.replacingOccurrences(of: device.name, with: device.displayName)
                .replacingOccurrences(of: "Unknown Device", with: device.displayName)
        return "\(event.title) · \(updated)"
    }
}

struct ServicesSectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner

    private var groups: [(String, [(NetworkDevice, NetworkServiceObservation)])] {
        let entries = scanner.devices.flatMap { device in device.serviceObservations.map { ($0.name, device, $0) } }
        let grouped = Dictionary(grouping: entries, by: { $0.0 })
        return grouped.keys.sorted().map { name in (name, grouped[name]!.map { ($0.1, $0.2) }) }
    }

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "Services", subtitle: "Advertised and directly reachable services observed on your LAN.")
            HStack(spacing: 14) {
                evidenceLegend("DISCOVERED", "Advertised through Bonjour/mDNS", .cyan)
                evidenceLegend("OPEN", "Accepted a direct TCP connection", .green)
                Spacer()
            }
            if groups.isEmpty {
                ContentUnavailableView("No services observed", systemImage: "square.stack.3d.up.slash",
                                       description: Text("Loom does not infer a service from an unobserved port."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(groups, id: \.0) { name, entries in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(name).font(.system(size: 15, weight: .semibold)); Spacer(); Text("\(entries.count) observations").font(.caption).foregroundStyle(LoomTheme.secondaryText) }
                                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                    let device = entry.0
                                    let service = entry.1
                                    HStack(spacing: 12) {
                                        DeviceGlyph(kind: device.displayKind, size: 32)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(device.displayName).font(.system(size: 12, weight: .medium))
                                            Text([device.ipAddress, service.port.map { "port \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                                .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                                        }
                                        Spacer()
                                        evidenceBadge(service.evidence)
                                    }
                                }
                            }.padding(16).glassCard(radius: 16)
                        }
                    }.padding(2)
                }.scrollIndicators(.hidden)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func evidenceLegend(_ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 8) { Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(color); Text(detail).font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText) }
    }
    private func evidenceBadge(_ evidence: ServiceEvidence) -> some View {
        Text(evidence.label).font(.system(size: 9, weight: .bold))
            .foregroundStyle(evidence == .discovered ? .cyan : LoomTheme.green)
            .padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct SecuritySectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    private var untrusted: [NetworkDevice] { scanner.devices.filter { !$0.isLocal && !$0.isTrusted } }

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "Security", subtitle: "An observational LAN overview—not vulnerability or antivirus scanning.")
            HStack(spacing: 14) {
                summary("\(untrusted.count)", "Needs Review", .orange, "questionmark.shield")
                summary("\(scanner.devices.filter { !$0.serviceObservations.isEmpty }.count)", "Devices with services", .cyan, "network")
                summary("\(scanner.devices.filter(\.isTrusted).count)", "Trusted", LoomTheme.green, "checkmark.shield")
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Needs Review").font(.system(size: 16, weight: .semibold))
                            Text("New or untrusted devices are not necessarily unsafe; they have not been marked as yours yet.")
                                .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                        }
                        Spacer()
                    }.padding(.horizontal, 4)
                    ForEach(untrusted) { device in
                        finding(icon: "questionmark.shield", color: .orange,
                                title: device.isNew ? "New device · needs review" : "Untrusted / Needs Review",
                                detail: "\(device.displayName) · \(device.ipAddress)", device: device)
                    }
                    if untrusted.isEmpty {
                        Label("No devices currently need review", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(LoomTheme.green).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(radius: 15)
                    }
                    HStack { Text("Observed Local Services").font(.system(size: 16, weight: .semibold)); Spacer() }
                        .padding(.horizontal, 4).padding(.top, 6)
                    ForEach(scanner.devices.filter { !$0.serviceObservations.isEmpty }) { device in
                        finding(icon: "network", color: .cyan,
                                title: "Local services are reachable or advertised",
                                detail: "\(device.displayName): \(device.serviceObservations.map(\.name).uniqued().joined(separator: ", "))",
                                device: device)
                    }
                    if scanner.devices.allSatisfy({ $0.serviceObservations.isEmpty }) {
                        Text("No local services have been observed. This does not represent a vulnerability scan.")
                            .font(.system(size: 12)).foregroundStyle(LoomTheme.secondaryText).padding(24).glassCard()
                    }
                }.padding(2)
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ value: String, _ label: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(color); VStack(alignment: .leading) { Text(value).font(.title2.bold()); Text(label).font(.caption).foregroundStyle(LoomTheme.secondaryText) }; Spacer() }
            .padding(16).frame(maxWidth: .infinity).glassCard(radius: 15)
    }
    private func finding(icon: String, color: Color, title: String, detail: String, device: NetworkDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 38)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText) }
            Spacer()
            Button { scanner.selectedDevice = device } label: {
                Text("Review").padding(.horizontal, 8).frame(height: 28)
            }
                .buttonStyle(LoomHoverButtonStyle(cornerRadius: 8, fillOpacity: 0.10, hoverScale: 1.035))
                .foregroundStyle(.cyan)
        }.padding(16).glassCard(radius: 15)
    }
}

struct SettingsSectionView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            SectionHeader(title: "Settings", subtitle: "Control local discovery, monitoring, notifications, and retained history.")
            ScrollView {
                VStack(spacing: 14) {
                    settingsGroup("General") {
                        Toggle("Scan automatically on launch", isOn: $settings.scanAutomatically)
                        Toggle("Background monitoring", isOn: $settings.backgroundMonitoring)
                        Toggle("Notify when a new device is discovered", isOn: $settings.notifyNewDevice)
                    }
                    settingsGroup("Discovery") {
                        Toggle("Automatic discovery", isOn: $settings.automaticDiscovery)
                        Toggle("Bonjour / mDNS discovery", isOn: $settings.bonjourDiscovery)
                        Toggle("Active subnet discovery", isOn: $settings.activeSubnetDiscovery)
                        Picker("Periodic broader rescan", selection: $settings.periodicRescanSeconds) {
                            Text("2 minutes").tag(120.0); Text("5 minutes").tag(300.0)
                            Text("10 minutes").tag(600.0); Text("30 minutes").tag(1800.0)
                        }
                    }
                    settingsGroup("Services") {
                        Toggle("Service discovery", isOn: $settings.serviceDiscovery)
                        Toggle("Check common local-network services", isOn: $settings.commonServiceChecks)
                    }
                    settingsGroup("Notifications") {
                        Toggle("New device", isOn: $settings.notifyNewDevice)
                        Toggle("Device returned", isOn: $settings.notifyDeviceReturned)
                        Toggle("Important network changes", isOn: $settings.notifyImportantChanges)
                    }
                    settingsGroup("Privacy") {
                        Label("Network observations and device history remain local on this Mac.", systemImage: "lock.shield")
                            .foregroundStyle(LoomTheme.secondaryText)
                    }
                    settingsGroup("Data") {
                        LabeledContent("Remembered devices", value: "\(scanner.devices.count)")
                        LabeledContent("Activity events", value: "\(scanner.activities.count)")
                        HStack { Button("Clear Device History", role: .destructive) { scanner.clearDeviceHistory() }; Button("Clear Activity History", role: .destructive) { scanner.clearActivityHistory() }; Spacer() }
                    }
                }.padding(2)
            }.scrollIndicators(.hidden)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: settings.notifyNewDevice) { _, _ in settings.requestNotificationPermissionIfNeeded() }
        .onChange(of: settings.notifyDeviceReturned) { _, _ in settings.requestNotificationPermissionIfNeeded() }
        .onChange(of: settings.notifyImportantChanges) { _, _ in settings.requestNotificationPermissionIfNeeded() }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content().toggleStyle(.switch)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).glassCard(radius: 16)
    }
}

struct DeviceInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scanner: NetworkScanner
    let device: NetworkDevice
    @State private var showsCustomization = false

    private var current: NetworkDevice { scanner.devices.first(where: { $0.id == device.id }) ?? device }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 15) {
                        ZStack(alignment: .bottomTrailing) {
                            DeviceGlyph(kind: current.displayKind, size: 68).opacity(current.isOnline ? 1 : 0.55)
                            if current.isTrusted { TrustedShieldBadge(size: 20) }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(current.displayName).font(.system(size: 23, weight: .bold)); if current.isNew { Text("NEW").font(.caption2.bold()).foregroundStyle(.orange) } }
                            HStack(spacing: 7) { StatusDot(color: current.isOnline ? LoomTheme.green : .gray); Text(current.isOnline ? "Online" : "Offline") }
                                .font(.system(size: 12)).foregroundStyle(LoomTheme.secondaryText)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(LoomTheme.secondaryText)
                        }
                        .buttonStyle(LoomHoverButtonStyle(cornerRadius: 18, fillOpacity: 0.10, hoverScale: 1.08))
                        .help("Close")
                    }
                    HStack {
                        Button(current.isTrusted ? "Mark as Needs Review" : "Mark as Trusted") { scanner.toggleTrusted(current) }
                            .buttonStyle(.borderedProminent).tint(current.isTrusted ? .gray : .blue)
                        Button("Customize Device") { showsCustomization = true }.buttonStyle(.bordered)
                        Button(scanner.inspectionDeviceID == current.id ? "Inspecting…" : "Inspect Common Ports") {
                            scanner.inspectCommonPorts(on: current)
                        }.buttonStyle(.bordered).disabled(!current.isOnline || scanner.inspectionDeviceID != nil)
                        Spacer()
                    }
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Customization").font(.system(size: 14, weight: .semibold))
                            Text(current.customName ?? "Automatic name: \(current.automaticDisplayName)")
                                .font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                            Text(current.customKind.map { "Custom category: \($0.categoryLabel)" }
                                 ?? "Automatic category: \(current.detectedKindLabel)")
                                .font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                        }
                        Spacer()
                        Button("Customize…") { showsCustomization = true }.buttonStyle(.borderedProminent)
                    }.padding(16).glassCard(radius: 15)
                    VStack(spacing: 0) {
                        detail("Detected Name", current.detectedName)
                        detail("IP Address", current.ipAddress)
                        detail("MAC Address", current.formattedMACAddress ?? "Unavailable")
                        detail("MAC Type", current.macTypeLabel)
                        detail("Vendor", current.vendorLabel)
                        detail("Hostname", current.hostname ?? "Unavailable")
                        detail("Detected Type", current.detectedKindLabel)
                        detail("Displayed Category", current.displayKindLabel)
                        detail("Trust", current.isTrusted ? "Trusted" : "Untrusted / Needs Review")
                        detail("Latency", current.latencyMS.map { "\($0) ms" } ?? "Unavailable")
                        detail("First Seen", current.firstSeen.formatted(date: .abbreviated, time: .shortened))
                        detail("Last Seen", current.lastSeen.formatted(date: .abbreviated, time: .shortened))
                    }.glassCard(radius: 15)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Observed Services").font(.system(size: 14, weight: .semibold))
                        if current.serviceObservations.isEmpty {
                            Text("No services have been advertised or directly observed.").font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                        } else {
                            ForEach(current.serviceObservations) { service in
                                HStack {
                                    Image(systemName: service.evidence == .open ? "point.3.connected.trianglepath.dotted" : "dot.radiowaves.left.and.right").foregroundStyle(service.evidence == .open ? LoomTheme.green : .cyan)
                                    Text(service.name).font(.system(size: 12, weight: .medium))
                                    if let port = service.port { Text("Port \(port)").font(.caption).foregroundStyle(LoomTheme.secondaryText) }
                                    Spacer(); Text(service.evidence.label).font(.caption2.bold()).foregroundStyle(service.evidence == .open ? LoomTheme.green : .cyan)
                                }
                            }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(radius: 15)
                    Text("All values shown here come from local observations. Unavailable fields are never inferred or fabricated.")
                        .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                }.padding(26)
            }.scrollIndicators(.hidden)
        }.frame(width: 650, height: 760)
        .sheet(isPresented: $showsCustomization) {
            DeviceCustomizationView(device: current).environmentObject(scanner)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(LoomTheme.secondaryText); Spacer(); Text(value).lineLimit(1).textSelection(.enabled) }
            .font(.system(size: 12)).padding(.horizontal, 15).frame(height: 42)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

struct DeviceCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scanner: NetworkScanner
    let device: NetworkDevice
    @State private var customName: String
    @State private var customKind: DeviceKind?
    @State private var isTrusted: Bool

    init(device: NetworkDevice) {
        self.device = device
        _customName = State(initialValue: device.customName ?? "")
        _customKind = State(initialValue: device.customKind)
        _isTrusted = State(initialValue: device.isTrusted)
    }

    private var current: NetworkDevice { scanner.devices.first(where: { $0.id == device.id }) ?? device }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    DeviceGlyph(kind: customKind ?? current.kind, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Customize Device").font(.system(size: 21, weight: .bold))
                        Text("Automatic detection remains preserved underneath your choices.")
                            .font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .buttonStyle(LoomHoverButtonStyle(cornerRadius: 18, fillOpacity: 0.1, hoverScale: 1.08))
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Friendly Name").font(.system(size: 13, weight: .semibold))
                    TextField("Use automatic name", text: $customName).textFieldStyle(.roundedBorder)
                    Text("Automatic: \(current.automaticDisplayName)")
                        .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                }.padding(15).glassCard(radius: 14)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Device Category").font(.system(size: 13, weight: .semibold))
                    Picker("Category", selection: $customKind) {
                        Text("Automatic — \(current.detectedKindLabel)").tag(DeviceKind?.none)
                        ForEach(DeviceKind.customizationOptions, id: \.self) { kind in
                            Label(kind.categoryLabel, systemImage: kind.symbol).tag(DeviceKind?.some(kind))
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Text("Automatic detection is not overwritten when a custom category is selected.")
                        .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                }.padding(15).glassCard(radius: 14)

                Toggle(isOn: $isTrusted) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trusted Device").font(.system(size: 13, weight: .semibold))
                        Text("Off means this device still needs your review—not that it is malicious.")
                            .font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
                    }
                }.toggleStyle(.switch).padding(15).glassCard(radius: 14)

                HStack {
                    Button("Reset Name & Category") {
                        customName = ""
                        customKind = nil
                    }.buttonStyle(.bordered)
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Save Changes") {
                        scanner.customizeDevice(current, customName: customName,
                                                customKind: customKind, isTrusted: isTrusted)
                        dismiss()
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24)
        }.frame(width: 540, height: 570)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)).sorted { String(describing: $0) < String(describing: $1) } }
}

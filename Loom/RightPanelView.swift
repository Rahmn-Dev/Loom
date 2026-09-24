import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject private var scanner: NetworkScanner

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                networkCard
                healthCard
                statsCard
                activityCard
                securityCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 22)
        }
        .scrollIndicators(.hidden)
    }

    private var networkCard: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color.cyan.opacity(0.17)); Image(systemName: "wifi").foregroundStyle(.cyan).font(.title2) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(scanner.interface.name).font(.system(size: 14, weight: .medium))
                Text(scanner.interface.cidr).font(.system(size: 12)).foregroundStyle(LoomTheme.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(); Image(systemName: "chevron.down").foregroundStyle(LoomTheme.secondaryText)
        }.padding(15).glassCard(radius: 17)
    }

    private var healthCard: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(LoomTheme.green.opacity(0.14)); StatusDot(size: 10) }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text("Network Health").font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                Text(scanner.interface.ipAddress == "—" ? "Offline" : "Excellent").font(.system(size: 22, weight: .bold))
                Text("\(scanner.onlineDevices.count) devices online").font(.system(size: 12)).foregroundStyle(LoomTheme.secondaryText)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(LoomTheme.secondaryText)
        }.padding(17).glassCard(radius: 17)
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat("\(scanner.onlineDevices.count)", "Devices Online", .cyan)
            Divider().frame(height: 48).overlay(Color.white.opacity(0.08))
            stat("\(scanner.devices.filter { !$0.isOnline }.count)", "Offline", LoomTheme.secondaryText)
            Divider().frame(height: 48).overlay(Color.white.opacity(0.08))
            stat("\(scanner.devices.count)", "Known", .orange)
        }.padding(.vertical, 14).glassCard(radius: 17)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 7) {
            Text(value).font(.system(size: 21, weight: .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(LoomTheme.secondaryText).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("Recent Activity").font(.system(size: 14, weight: .semibold)); Spacer(); Text("Live").font(.system(size: 11)).foregroundStyle(.cyan) }
            if scanner.activities.isEmpty {
                Text("New devices will appear here as they are detected.").font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                    .padding(.vertical, 10)
            } else {
                ForEach(scanner.activities.prefix(4)) { item in
                    HStack(spacing: 10) {
                        DeviceGlyph(kind: activityDeviceKind(item), size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activityDeviceName(item)).font(.system(size: 12, weight: .medium))
                            Text(activityDetail(item)).font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText).lineLimit(1)
                        }
                        Spacer(); Text(item.date.formatted(.relative(presentation: .numeric))).font(.system(size: 9)).foregroundStyle(LoomTheme.secondaryText)
                    }
                }
            }
        }.padding(16).glassCard(radius: 17)
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("Network Security").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").font(.caption) }
            securityLine("\(scanner.devices.filter { !$0.isTrusted && !$0.isLocal && !$0.isGateway }.count) devices need review",
                         icon: "questionmark.shield.fill", color: .orange)
            securityLine("\(scanner.devices.flatMap(\.serviceObservations).count) service observations",
                         icon: "network", color: .cyan)
            securityLine("Observations stay on this Mac", icon: "lock.fill", color: LoomTheme.green)
        }.padding(16).glassCard(radius: 17)
    }

    private func securityLine(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 21)
            Text(label).font(.system(size: 11.5)); Spacer()
        }
    }

    private func activityDeviceName(_ item: ActivityItem) -> String {
        guard let id = item.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else { return item.title }
        return device.displayName
    }

    private func activityDeviceKind(_ item: ActivityItem) -> DeviceKind {
        guard let id = item.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else { return item.kind }
        return device.displayKind
    }

    private func activityDetail(_ item: ActivityItem) -> String {
        guard let id = item.deviceID,
              let device = scanner.devices.first(where: { $0.id == id }) else {
            return "\(item.title) · \(item.detail)"
        }
        let updated = item.detail.contains(device.displayName)
            ? item.detail
            : item.detail.replacingOccurrences(of: device.name, with: device.displayName)
                .replacingOccurrences(of: "Unknown Device", with: device.displayName)
        return "\(item.title) · \(updated)"
    }
}

import SwiftUI

struct DeviceTableView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @State private var query = ""

    private var filtered: [NetworkDevice] {
        guard !query.isEmpty else { return scanner.devices }
        return scanner.devices.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.ipAddress.contains(query) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Discovered Devices").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if geometry.size.width >= 560 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(LoomTheme.secondaryText)
                            TextField("Search devices…", text: $query).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12).frame(maxWidth: 260).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(LoomTheme.stroke)))
                    }
                    Spacer(minLength: 4)
                    Text("All  \(scanner.devices.count)").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(LoomTheme.primary.opacity(0.5)))
                    if geometry.size.width >= 780 {
                        Text("Online  \(scanner.onlineDevices.count)").font(.system(size: 12)).foregroundStyle(LoomTheme.secondaryText)
                    }
                }.padding(.horizontal, 18).frame(height: 55)

                Divider().overlay(Color.white.opacity(0.08))
                tableHeader(width: geometry.size.width)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { device in
                            row(device, width: geometry.size.width)
                            Divider().overlay(Color.white.opacity(0.055)).padding(.leading, 18)
                        }
                    }
                }
            }
            .glassCard(radius: 17)
        }
    }

    private func tableHeader(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            header("Device", width: deviceColumnWidth(for: width))
            if width >= 460 { header("IP Address", width: 115) }
            if width >= 850 { header("MAC Address", width: 145) }
            if width >= 590 { header("Type", width: 95) }
            if width >= 730 { header("Connection", width: 130) }
            if width >= 650 { header("Last Seen", width: 82) }
            Spacer()
        }.padding(.horizontal, 16).frame(height: 31).background(Color.white.opacity(0.035))
    }

    private func header(_ title: String, width: CGFloat) -> some View {
        Text(title).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText).frame(width: width, alignment: .leading)
    }

    private func row(_ device: NetworkDevice, width: CGFloat) -> some View {
        Button { scanner.selectedDevice = device } label: {
            HStack(spacing: 0) {
                HStack(spacing: 9) {
                    DeviceGlyph(kind: device.kind, size: 25)
                    Text(device.displayName).lineLimit(1)
                }.frame(width: deviceColumnWidth(for: width), alignment: .leading)
                if width >= 460 {
                    Text(device.ipAddress).frame(width: 115, alignment: .leading).foregroundStyle(LoomTheme.secondaryText)
                }
                if width >= 850 {
                    Text(device.formattedMACAddress ?? "—").frame(width: 145, alignment: .leading).foregroundStyle(LoomTheme.secondaryText)
                }
                if width >= 590 {
                    Text(device.kind.rawValue.capitalized).frame(width: 95, alignment: .leading).foregroundStyle(LoomTheme.secondaryText)
                }
                if width >= 730 {
                    HStack(spacing: 7) {
                        StatusDot(color: device.isOnline ? LoomTheme.green : .gray, size: 6)
                        Text(device.isOnline ? device.connectionLabel : "Offline").lineLimit(1)
                    }
                        .frame(width: 130, alignment: .leading).foregroundStyle(LoomTheme.secondaryText)
                }
                if width >= 650 {
                    Text(device.lastSeen.formatted(.relative(presentation: .named))).frame(width: 82, alignment: .leading)
                        .foregroundStyle(LoomTheme.secondaryText)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(LoomTheme.secondaryText)
            }
            .font(.system(size: 11.5)).padding(.horizontal, 16).frame(height: 36)
            .contentShape(Rectangle())
        }.buttonStyle(LoomHoverButtonStyle(cornerRadius: 7, fillOpacity: 0.075, hoverScale: 1.002))
    }

    private func deviceColumnWidth(for width: CGFloat) -> CGFloat {
        width < 520 ? min(175, max(145, width - 165)) : (width < 800 ? 175 : 185)
    }
}

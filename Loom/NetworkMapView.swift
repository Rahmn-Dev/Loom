import SwiftUI

struct NetworkMapView: View {
    @EnvironmentObject private var scanner: NetworkScanner

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
            let compact = geometry.size.width < 700 || geometry.size.height < 310
            let candidates = scanner.devices.filter { !$0.isGateway }
            let displayedDevices = Array(candidates.prefix(compact ? 4 : 20))
            ZStack {
                ForEach(1..<5) { ring in
                    Circle().stroke(Color.cyan.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                        .frame(width: CGFloat(ring) * 88, height: CGFloat(ring) * 88)
                        .position(center)
                }

                ForEach(Array(displayedDevices.enumerated()), id: \.element.id) { index, device in
                    let point = point(index: index, total: max(displayedDevices.count, 1), center: center,
                                      size: geometry.size, compact: compact)
                    Path { path in path.move(to: center); path.addLine(to: point) }
                        .stroke(LinearGradient(colors: [device.isOnline ? .cyan.opacity(0.72) : .gray.opacity(0.35),
                                                        .purple.opacity(0.28)],
                                               startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                    Circle().fill(device.isOnline ? Color.cyan : Color.gray).frame(width: 5, height: 5)
                        .shadow(color: device.isOnline ? .cyan : .clear, radius: 5).position(midpoint(center, point))
                    Button { scanner.selectedDevice = device } label: {
                        DeviceNode(device: device, compact: compact)
                    }
                    .buttonStyle(LoomHoverButtonStyle(cornerRadius: 22, fillOpacity: 0.055, hoverScale: 1.055))
                    .help("Open \(device.displayName)")
                    .position(point)
                }

                if let gateway = scanner.devices.first(where: \.isGateway) {
                    Button { scanner.selectedDevice = gateway } label: {
                        RouterNode(device: gateway, scanning: scanner.isScanning, compact: compact)
                    }
                    .buttonStyle(LoomHoverButtonStyle(cornerRadius: 24, fillOpacity: 0.045, hoverScale: 1.035))
                    .help("Open \(gateway.displayName)")
                    .position(center)
                } else {
                    RouterNode(device: nil, scanning: scanner.isScanning, compact: compact).position(center)
                }

                if displayedDevices.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(.cyan)
                        Text("Looking for devices…").foregroundStyle(LoomTheme.secondaryText)
                    }
                    .offset(y: 125)
                }

                if candidates.count > displayedDevices.count {
                    Text("+\(candidates.count - displayedDevices.count) more devices")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LoomTheme.secondaryText)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.22)))
                        .position(x: geometry.size.width - 85, y: geometry.size.height - 20)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: displayedDevices.map(\.id))
        }
    }

    private func point(index: Int, total: Int, center: CGPoint, size: CGSize, compact: Bool) -> CGPoint {
        let firstRingCount = compact ? total : min(total, 8)
        let onOuterRing = !compact && index >= firstRingCount
        let ringIndex = onOuterRing ? index - firstRingCount : index
        let ringTotal = onOuterRing ? max(total - firstRingCount, 1) : max(firstRingCount, 1)
        let offset = onOuterRing ? Double.pi / Double(ringTotal) : 0
        let angle = (Double(ringIndex) / Double(ringTotal)) * .pi * 2 - .pi / 2 + offset
        let scale: CGFloat = onOuterRing ? 1 : (total > 8 ? 0.64 : 1)
        let availableX = max(80, size.width / 2 - (compact ? 60 : 68))
        let availableY = max(70, size.height / 2 - (compact ? 54 : 64))
        let radiusX = min(size.width * (compact ? 0.36 : 0.42), 430, availableX) * scale
        let radiusY = min(size.height * (compact ? 0.33 : 0.39), 250, availableY) * scale
        return CGPoint(x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }
}

private struct DeviceNode: View {
    let device: NetworkDevice
    let compact: Bool
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Color(red: 0.06, green: 0.10, blue: 0.26).opacity(0.95))
                Circle().stroke(device.kind.tint.opacity(0.78), lineWidth: 1.2)
                DeviceGlyph(kind: device.kind, size: 43)
            }.frame(width: compact ? 58 : 76, height: compact ? 58 : 76)
                .shadow(color: device.kind.tint.opacity(0.32), radius: 13)
            HStack(spacing: 4) {
                StatusDot(color: device.isOnline ? LoomTheme.green : .gray, size: 7)
                Text(device.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            if !compact {
                Text(device.ipAddress).font(.system(size: 10)).foregroundStyle(LoomTheme.secondaryText)
            }
        }.frame(width: 120).opacity(device.isOnline ? 1 : 0.58)
    }
}

private struct RouterNode: View {
    let device: NetworkDevice?
    let scanning: Bool
    let compact: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.10)).frame(width: compact ? 104 : 145, height: compact ? 104 : 145)
                Circle().stroke(Color.cyan.opacity(0.16), lineWidth: 1).frame(width: compact ? 92 : 128, height: compact ? 92 : 128)
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.05, green: 0.08, blue: 0.20))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.55)))
                    .frame(width: compact ? 82 : 108, height: compact ? 50 : 66)
                Image(systemName: "wifi.router.fill").font(.system(size: compact ? 36 : 48)).foregroundStyle(
                    LinearGradient(colors: [.white, .blue], startPoint: .top, endPoint: .bottom))
            }
            HStack(spacing: 5) {
                StatusDot(color: device?.isOnline == false ? .gray : LoomTheme.green)
                Text(device?.displayName ?? "Your Network").font(.system(size: 14, weight: .semibold))
            }
            Text(scanning ? "Scanning" : (device?.isOnline == false ? "Not observed" : "Online"))
                .font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
        }
    }
}

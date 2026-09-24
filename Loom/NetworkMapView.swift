import SwiftUI

/// Layouts use each node's full hit area, so labels and hover affordances remain selectable.
private struct TopologyPlacement: Identifiable {
    let device: NetworkDevice
    let point: CGPoint
    let scale: CGFloat
    var id: String { device.id }
}

private struct TopologyPlan {
    let placements: [TopologyPlacement]
    let hiddenCount: Int
    let isCondensed: Bool

    static func make(devices: [NetworkDevice], size: CGSize) -> TopologyPlan {
        guard !devices.isEmpty, size.width > 80, size.height > 80 else {
            return TopologyPlan(placements: [], hiddenCount: devices.count, isCondensed: true)
        }

        // Reduce a complete node—including its label—before using more positions.
        let baseScale = min(1, max(0.48, min(size.width / 900, size.height / 410)))
        let densityScale = devices.count <= 6 ? 1 : max(0.56, sqrt(6 / CGFloat(devices.count)) * 1.12)
        let scale = min(1, max(0.48, baseScale * densityScale))
        let condensed = scale < 0.76
        let nodeWidth = max(70, 120 * scale)
        let nodeHeight = condensed ? max(62, 80 * scale) : max(84, 108 * scale)
        let halfWidth = nodeWidth / 2 + 8
        let halfHeight = nodeHeight / 2 + 8
        let columns = max(1, Int(floor((size.width - halfWidth * 2) / (nodeWidth + 16))) + 1)
        let rows = max(1, Int(floor((size.height - halfHeight * 2) / (nodeHeight + 18))) + 1)
        let xStep = columns > 1 ? (size.width - halfWidth * 2) / CGFloat(columns - 1) : 0
        let yStep = rows > 1 ? (size.height - halfHeight * 2) / CGFloat(rows - 1) : 0
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 8)

        // Keep a clear zone for the router, its labels, and its hover state.
        let routerWidth: CGFloat = condensed ? 122 : 168
        let routerHeight: CGFloat = condensed ? 118 : 154
        let routerClearX = routerWidth / 2 + halfWidth + 10
        let routerClearY = routerHeight / 2 + halfHeight + 10

        var candidates: [CGPoint] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let stagger = row.isMultiple(of: 2) || columns == 1 ? 0 : min(xStep * 0.22, nodeWidth * 0.22)
                let x = min(size.width - halfWidth, max(halfWidth, halfWidth + CGFloat(column) * xStep + stagger))
                let y = halfHeight + CGFloat(row) * yStep
                guard abs(x - center.x) >= routerClearX || abs(y - center.y) >= routerClearY else { continue }
                candidates.append(CGPoint(x: x, y: y))
            }
        }
        guard !candidates.isEmpty else {
            return TopologyPlan(placements: [], hiddenCount: devices.count, isCondensed: true)
        }

        // Sample safe positions clockwise around the gateway to retain a map-like shape.
        let clockwise = candidates.sorted {
            let lhsAngle = atan2($0.y - center.y, $0.x - center.x)
            let rhsAngle = atan2($1.y - center.y, $1.x - center.x)
            if lhsAngle == rhsAngle {
                return hypot($0.x - center.x, $0.y - center.y) > hypot($1.x - center.x, $1.y - center.y)
            }
            return lhsAngle < rhsAngle
        }
        let visibleCount = min(devices.count, clockwise.count, 20)
        let selected = (0..<visibleCount).map { index in
            clockwise[min(clockwise.count - 1, Int(Double(index) * Double(clockwise.count) / Double(visibleCount)))]
        }
        let placements = zip(devices.prefix(visibleCount), selected).map {
            TopologyPlacement(device: $0.0, point: $0.1, scale: scale)
        }
        return TopologyPlan(placements: placements, hiddenCount: devices.count - visibleCount, isCondensed: condensed)
    }
}

struct NetworkMapView: View {
    @EnvironmentObject private var scanner: NetworkScanner

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 + 8)
            let candidates = scanner.devices.filter { !$0.isGateway }
            let plan = TopologyPlan.make(devices: candidates, size: geometry.size)
            ZStack {
                ForEach(1..<4) { ring in
                    Ellipse()
                        .stroke(Color.cyan.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                        .frame(width: max(80, geometry.size.width * CGFloat(ring) / 3.4),
                               height: max(70, geometry.size.height * CGFloat(ring) / 3.8))
                        .position(center)
                }

                ForEach(plan.placements) { placement in
                    Path { path in path.move(to: center); path.addLine(to: placement.point) }
                        .stroke(LinearGradient(colors: [placement.device.isOnline ? .cyan.opacity(0.62) : .gray.opacity(0.30), .purple.opacity(0.24)], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                    Circle().fill(placement.device.isOnline ? Color.cyan : Color.gray).frame(width: 5, height: 5)
                        .shadow(color: placement.device.isOnline ? .cyan : .clear, radius: 5)
                        .position(midpoint(center, placement.point))
                    Button { scanner.selectedDevice = placement.device } label: {
                        DeviceNode(device: placement.device, scale: placement.scale)
                    }
                    .buttonStyle(LoomHoverButtonStyle(cornerRadius: 18, fillOpacity: 0.055, hoverScale: 1.025))
                    .help("Open \(placement.device.displayName)")
                    .position(placement.point)
                }

                if let gateway = scanner.devices.first(where: \.isGateway) {
                    Button { scanner.selectedDevice = gateway } label: {
                        RouterNode(device: gateway, scanning: scanner.isScanning, compact: plan.isCondensed)
                    }
                    .buttonStyle(LoomHoverButtonStyle(cornerRadius: 24, fillOpacity: 0.045, hoverScale: 1.025))
                    .help("Open \(gateway.displayName)")
                    .position(center)
                } else {
                    RouterNode(device: nil, scanning: scanner.isScanning, compact: plan.isCondensed).position(center)
                }

                if candidates.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(.cyan)
                        Text("Looking for devices…").foregroundStyle(LoomTheme.secondaryText)
                    }.offset(y: 125)
                }
                if plan.hiddenCount > 0 {
                    Text("+\(plan.hiddenCount) more devices")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(LoomTheme.secondaryText)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.22)))
                        .position(x: geometry.size.width - 85, y: geometry.size.height - 20)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: plan.placements.map(\.id))
        }
    }

    private func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }
}

private struct DeviceNode: View {
    let device: NetworkDevice
    let scale: CGFloat
    private var condensed: Bool { scale < 0.76 }
    private var nodeWidth: CGFloat { max(70, 120 * scale) }
    private var orbSize: CGFloat { max(48, 76 * scale) }

    var body: some View {
        VStack(spacing: condensed ? 3 : 5) {
            ZStack {
                Circle().fill(Color(red: 0.06, green: 0.10, blue: 0.26).opacity(0.95))
                Circle().stroke(device.displayKind.tint.opacity(0.78), lineWidth: 1.2)
                DeviceGlyph(kind: device.displayKind, size: max(29, 43 * scale))
                if device.isTrusted {
                    TrustedShieldBadge(size: max(13, 18 * scale))
                        .offset(x: orbSize * 0.37, y: orbSize * 0.37)
                }
            }
            .frame(width: orbSize, height: orbSize)
            .shadow(color: device.displayKind.tint.opacity(0.32), radius: 10 * scale)
            HStack(spacing: 4) {
                StatusDot(color: device.isOnline ? LoomTheme.green : .gray, size: max(5, 7 * scale))
                Text(device.displayName).font(.system(size: max(9, 12 * scale), weight: .semibold)).lineLimit(1)
            }
            if !condensed {
                Text(device.ipAddress).font(.system(size: max(8, 10 * scale))).foregroundStyle(LoomTheme.secondaryText)
            }
        }
        .frame(width: nodeWidth)
        .opacity(device.isOnline ? 1 : 0.58)
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
                Image(systemName: "wifi.router.fill").font(.system(size: compact ? 36 : 48)).foregroundStyle(LinearGradient(colors: [.white, .blue], startPoint: .top, endPoint: .bottom))
                if device?.isTrusted == true {
                    TrustedShieldBadge(size: compact ? 16 : 19)
                        .offset(x: compact ? 34 : 45, y: compact ? 21 : 28)
                }
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

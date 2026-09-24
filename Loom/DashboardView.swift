import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @State private var selection = "Overview"

    var body: some View {
        GeometryReader { geometry in
            let compactSidebar = geometry.size.width < 1080
            let showInspector = geometry.size.width >= 1220
            ZStack {
                AppBackground()
                HStack(spacing: 0) {
                    SidebarView(selection: $selection, compact: compactSidebar)
                    sectionContent(compact: geometry.size.width < 900)
                    if showInspector && selection == "Overview" {
                        RightPanelView().frame(width: min(292, geometry.size.width * 0.21))
                            .background(Color.black.opacity(0.06))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .sheet(item: $scanner.selectedDevice) { device in DeviceInspectorView(device: device) }
    }

    @ViewBuilder
    private func sectionContent(compact: Bool) -> some View {
        switch selection {
        case "Devices": DevicesSectionView()
        case "Network Map": NetworkMapSectionView()
        case "Activity": ActivitySectionView()
        case "Services": ServicesSectionView()
        case "Security": SecuritySectionView()
        case "Settings": SettingsSectionView()
        default: mainContent(compact: compact)
        }
    }

    private func mainContent(compact: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scanner.isScanning ? "Scanning Your Network…" : "Your Network at a Glance")
                        .font(.system(size: compact ? 21 : 27, weight: .bold)).lineLimit(1).minimumScaleFactor(0.72)
                    Text(scanner.isScanning && !scanner.scanTarget.isEmpty
                         ? "Scanning \(scanner.scanTarget) · devices appear as they are observed."
                         : scanner.phase.label)
                        .font(.system(size: 14)).foregroundStyle(LoomTheme.secondaryText)
                }
                Spacer()
                Button {
                    scanner.isScanning ? scanner.stopScanning() : scanner.startScanning()
                } label: {
                    Text(scanner.isScanning ? "Stop Scan" : "Scan Again")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(LoomTheme.stroke)))
                }
                .buttonStyle(LoomHoverButtonStyle(cornerRadius: 11, fillOpacity: 0.10, hoverScale: 1.025))
            }
            .padding(.horizontal, 16).padding(.top, 28)

            NetworkMapView().frame(maxHeight: .infinity)
            DeviceTableView().frame(height: compact ? 250 : 305)
        }
        .padding(.horizontal, 16).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}

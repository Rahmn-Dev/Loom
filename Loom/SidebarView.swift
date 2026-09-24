import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var scanner: NetworkScanner
    @Binding var selection: String
    let compact: Bool
    private let entries = [
        ("Overview", "house.fill"), ("Devices", "display.2"), ("Network Map", "point.3.connected.trianglepath.dotted"),
        ("Activity", "chart.bar.xaxis"), ("Services", "square.grid.2x2"), ("Security", "shield"), ("Settings", "gearshape")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: compact ? 0 : 14) {
                ZStack {
                    Circle().fill(AngularGradient(colors: [.cyan, .blue, .purple, .cyan], center: .center))
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 21, height: 31).rotationEffect(.degrees(20))
                }
                .frame(width: 43, height: 43)
                .shadow(color: .cyan.opacity(0.65), radius: 10)
                if !compact {
                    Text("Loom").font(.system(size: 27, weight: .bold, design: .rounded))
                }
            }
            .padding(.top, 58)
            .frame(maxWidth: .infinity)

            if !compact {
                Text("Your Home Network\nAt a Glance")
                    .font(.system(size: 13)).foregroundStyle(LoomTheme.secondaryText).lineSpacing(5)
                    .padding(.top, 18).padding(.horizontal, 28)
            }

            VStack(spacing: 6) {
                ForEach(entries, id: \.0) { entry in
                    Button {
                        selection = entry.0
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: entry.1).frame(width: 22)
                                .foregroundStyle(selection == entry.0 ? .white : Color(red: 0.65, green: 0.73, blue: 1))
                            if !compact {
                                Text(entry.0).font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                        }
                        .padding(.horizontal, compact ? 14 : 16).frame(height: 47)
                        .background(RoundedRectangle(cornerRadius: 12).fill(selection == entry.0 ? Color.white.opacity(0.15) : .clear))
                    }
                    .buttonStyle(LoomHoverButtonStyle(cornerRadius: 12, fillOpacity: 0.11, hoverScale: 1.025))
                    .help(entry.0)
                }
            }
            .padding(.horizontal, compact ? 10 : 14).padding(.top, compact ? 30 : 36)

            Spacer()

            if compact {
                ZStack {
                    Circle().stroke(Color.cyan.opacity(0.25), lineWidth: 5)
                    Circle().trim(from: 0, to: scanner.progress).stroke(
                        LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.cyan)
                }
                .frame(width: 42, height: 42).frame(maxWidth: .infinity).padding(.bottom, 18)
                .help(scanner.phase.label)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(Color.cyan.opacity(0.25), lineWidth: 7)
                        Circle().trim(from: 0, to: scanner.progress).stroke(
                            LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.cyan)
                    }.frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scanner.isScanning ? "Scanning Network…" : "Network Ready")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(scanner.phase.label).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText).lineLimit(2)
                    }
                }
                ProgressView(value: scanner.progress).tint(.cyan)
                HStack {
                    Text(scanner.interface.cidr).font(.system(size: 11)).foregroundStyle(LoomTheme.secondaryText)
                    Spacer()
                    Text("\(Int(scanner.progress * 100))%").font(.system(size: 12, weight: .semibold))
                }
                }
                .padding(16).glassCard(radius: 15).padding(14)
            }
        }
        .frame(width: compact ? 76 : 224)
        .background(Color(red: 0.08, green: 0.07, blue: 0.22).opacity(0.62))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1) }
    }
}

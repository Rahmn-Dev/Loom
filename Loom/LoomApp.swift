import SwiftUI

@main
struct LoomApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var scanner: NetworkScanner

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _scanner = StateObject(wrappedValue: NetworkScanner(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(scanner)
                .environmentObject(settings)
                .frame(minWidth: 720, minHeight: 600)
                .preferredColorScheme(.dark)
                .task {
                    if settings.scanAutomatically && settings.automaticDiscovery {
                        scanner.startScanning()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("Scan") {
                Button(scanner.isScanning ? "Stop Scan" : "Scan Again") {
                    scanner.isScanning ? scanner.stopScanning() : scanner.startScanning()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
